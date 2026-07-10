module Api
  class BaseController < ActionController::Base
    skip_before_action :verify_authenticity_token
    before_action :authenticate_api_token!

    attr_reader :current_api_token

    private

    def authenticate_api_token!
      token = request.headers["Authorization"]&.delete_prefix("Bearer ")
      token ||= params[:token]

      if token.present?
        api_token = ApiToken.find_by(token: token)
        if api_token
          api_token.update_column(:last_used_at, Time.current)
          @current_api_token = api_token
          return
        end
      end

      # Allow unauthenticated access in development for easy testing
      return if Rails.env.development?

      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    # The project ingested into is determined by the API token (which belongs to
    # exactly one project), NOT by a client-supplied name — otherwise any valid
    # token could write to or create any project. Falls back to a name lookup
    # only in development, where requests may be unauthenticated.
    def token_project
      return current_api_token.project if current_api_token

      raise "no API token" unless Rails.env.development?

      name = request.headers["X-StaffOS-Project"] || params[:project_name] || "Default"
      Project.find_by(name: name) ||
        Project.create!(name: name, repo_name: params[:repo_name] || "unknown", user: User.order(:id).first)
    end
  end
end
