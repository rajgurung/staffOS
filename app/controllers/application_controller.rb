class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  before_action :authenticate_user!
  helper_method :current_project

  def current_project
    @current_project ||= if session[:project_id]
      Project.find_by(id: session[:project_id]) || Project.first
    else
      Project.first
    end
  end

  def switch_project
    project = Project.find(params[:project_id])
    session[:project_id] = project.id
    redirect_back fallback_location: root_path
  end
end
