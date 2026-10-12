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
    rules_before = @project.risk_rules
    if @project.update(project_params)
      # Rescore now rather than waiting for each branch's next session.
      # Generation is deterministic (no LLM calls), so this is cheap.
      if @project.risk_rules != rules_before
        @project.workstreams.joins(:run_passport).find_each { |ws| PassportGenerator.new(ws).generate! }
      end
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
    permitted = params.require(:project).except(:risk_rules, :risk_rules_submitted).permit(:name, :repo_name, :tech_stack)
    # The form always sends risk_rules_submitted, so removing every rule (which
    # sends no risk_rules at all) still saves an empty set.
    if params[:project][:risk_rules_submitted].present?
      rules = params[:project][:risk_rules]
      rules = rules.respond_to?(:to_unsafe_h) ? rules.to_unsafe_h : {}
      permitted[:risk_rules] = rules.to_h
        .transform_keys { |pattern| pattern.to_s.strip }
        .select { |pattern, level| pattern.present? && Project::RISK_LEVELS.include?(level) }
    end
    permitted
  end
end
