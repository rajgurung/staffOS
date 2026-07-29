class AgentSessionsController < ApplicationController
  before_action :require_current_project, only: :index

  def index
    @sessions = current_project.agent_sessions.includes(workstream: :run_passport).order(started_at: :desc)
    if params[:status].present?
      @sessions = @sessions.where(status: params[:status])
    else
      # Helper-process residue (transcript summarizers, ghosts) is hidden
      # unless explicitly requested via ?status=noise.
      @sessions = @sessions.where.not(status: "noise")
    end
    @sessions = @sessions.where("branch_name ILIKE ?", "%#{params[:branch]}%") if params[:branch].present?
  end

  def show
    @session = AgentSession.where(project: accessible_projects).find(params[:id])
    @events = @session.run_events.includes(:workstream).order(occurred_at: :asc)
    # Every branch this session touched — sessions can hop branches.
    @touched_workstreams = @session.touched_workstreams.includes(:run_passport).to_a
    @passports = @touched_workstreams.filter_map(&:run_passport).uniq
  end
end
