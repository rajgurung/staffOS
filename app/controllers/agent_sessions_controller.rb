class AgentSessionsController < ApplicationController
  before_action :require_current_project, only: :index

  def index
    @sessions = current_project.agent_sessions.includes(workstream: :run_passport).order(started_at: :desc)
    @sessions = @sessions.where(status: params[:status]) if params[:status].present?
    @sessions = @sessions.where("branch_name ILIKE ?", "%#{params[:branch]}%") if params[:branch].present?
  end

  def show
    @session = AgentSession.where(project: accessible_projects).find(params[:id])
    @events = @session.run_events.order(occurred_at: :asc)
    # Every branch passport this session fed — sessions can hop branches.
    @passports = @session.touched_workstreams.includes(:run_passport)
      .filter_map(&:run_passport).uniq
  end
end
