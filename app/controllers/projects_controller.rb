class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :destroy, :hook_config]

  def index
    @projects = Project.all.order(:name)
  end

  def show
    @recent_sessions = @project.agent_sessions.order(started_at: :desc).limit(5)
    @tokens = @project.api_tokens
    @workstreams = @project.workstreams.recent.includes(:run_passports, agent_sessions: :run_passport)
    @unassigned_sessions = @project.agent_sessions.where(workstream_id: nil).includes(:run_passport).order(started_at: :desc)
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)
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
    @project = Project.find(params[:id])
  end

  def project_params
    permitted = params.require(:project).permit(:name, :repo_name, :tech_stack)
    if params[:project][:risk_rules].present?
      permitted[:risk_rules] = params[:project][:risk_rules].to_unsafe_h
    end
    permitted
  end
end
