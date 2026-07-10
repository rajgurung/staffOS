class ApiTokensController < ApplicationController
  def create
    project = current_user.projects.find(params[:project_id])
    @token = project.api_tokens.create!(name: params[:name] || "Default")
    redirect_to project_path(project), notice: "API token created: #{@token.token}"
  end

  def destroy
    token = ApiToken.joins(:project).where(projects: { user_id: current_user.id }).find(params[:id])
    project = token.project
    token.destroy
    redirect_to project_path(project), notice: "API token revoked."
  end
end
