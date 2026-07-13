class ProjectsController < ApplicationController
  # Caps for the workstream tree so long-lived projects don't render their entire history
  TREE_WORKSTREAMS_LIMIT = 10
  TREE_SESSIONS_LIMIT = 5

  before_action :set_project, only: [:show, :edit, :update, :destroy, :hook_config]

  def index
    @projects = current_user.projects.order(:name)
  end

  def show
    @recent_sessions = @project.agent_sessions.order(started_at: :desc).limit(5)
    @tokens = @project.api_tokens
    @workstreams_total = @project.workstreams.count
    @workstreams = @project.workstreams.recent.limit(TREE_WORKSTREAMS_LIMIT).includes(:run_passport, :agent_sessions)
    unassigned = @project.agent_sessions.where(workstream_id: nil)
    @unassigned_total = unassigned.count
    @unassigned_sessions = unassigned.order(started_at: :desc).limit(TREE_SESSIONS_LIMIT)
  end

  def new
    @project = current_user.projects.new
  end

  def create
    @project = current_user.projects.new(project_params)
    if @project.save
      redirect_to @project, notice: "Project created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: "Project deleted."
  end

  def hook_config
    @token = @project.api_tokens.first
  end

  private

  def set_project
    @project = current_user.projects.find(params[:id])
  end

  def project_params
    permitted = params.require(:project).permit(:name, :repo_name, :tech_stack)
    if params[:project][:risk_rules].present?
      permitted[:risk_rules] = params[:project][:risk_rules].to_unsafe_h
    end
    permitted
  end
end
