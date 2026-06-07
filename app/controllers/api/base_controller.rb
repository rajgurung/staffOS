module Api
  class BaseController < ActionController::Base
    skip_before_action :verify_authenticity_token
    before_action :authenticate_api_token!

    private

    def authenticate_api_token!
      token = request.headers["Authorization"]&.delete_prefix("Bearer ")
      token ||= params[:token]

      if token.present?
        api_token = ApiToken.find_by(token: token)
        if api_token
          api_token.update_column(:last_used_at, Time.current)
          return
        end
      end

      # Allow unauthenticated access in development for easy testing
      return if Rails.env.development?

      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end
