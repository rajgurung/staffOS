class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  before_action :authenticate_user!
  helper_method :current_project

  def current_project
    return @current_project if defined?(@current_project)
    return @current_project = nil unless user_signed_in?

    # Scoped to the signed-in user's projects so a stale/forged project_id can
    # never surface another user's data. An explicit project_id param (e.g.
    # links from a project page) overrides the session switcher.
    scope = current_user.projects
    project = scope.find_by(id: params[:project_id]) || scope.find_by(id: session[:project_id]) || scope.first
    session[:project_id] = project.id if project
    @current_project = project
  end

  def switch_project
    project = current_user.projects.find(params[:project_id])
    session[:project_id] = project.id
    redirect_back fallback_location: root_path
  end

  private

  # The projects the signed-in user owns. Scope record lookups through this so a
  # show/edit action can't surface another user's data by guessed id.
  def accessible_projects
    current_user.projects
  end
end
