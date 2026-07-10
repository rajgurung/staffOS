class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  before_action :authenticate_user!
  helper_method :current_project

  def current_project
    @current_project ||= begin
      # An explicit project_id param (e.g. links from a project page) overrides
      # the session-based switcher and becomes the new context.
      project = Project.find_by(id: params[:project_id]) || Project.find_by(id: session[:project_id]) || Project.first
      session[:project_id] = project.id if project
      project
    end
  end

  def switch_project
    project = Project.find(params[:project_id])
    session[:project_id] = project.id
    redirect_back fallback_location: root_path
  end
end
