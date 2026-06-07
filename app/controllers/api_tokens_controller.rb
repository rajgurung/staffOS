class ApiTokensController < ApplicationController
  def create
    project = Project.find(params[:project_id])
    @token = project.api_tokens.create!(name: params[:name] || "Default")
    redirect_to project_path(project), notice: "API token created: #{@token.token}"
  end

  def destroy
    token = ApiToken.find(params[:id])
    project = token.project
    token.destroy
    redirect_to project_path(project), notice: "API token revoked."
  end
end
