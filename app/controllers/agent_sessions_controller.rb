class AgentSessionsController < ApplicationController
  before_action :require_current_project, only: :index

  def index
    @sessions = current_project.agent_sessions.includes(:run_passport).order(started_at: :desc)
    @sessions = @sessions.where(status: params[:status]) if params[:status].present?
    @sessions = @sessions.where("branch_name ILIKE ?", "%#{params[:branch]}%") if params[:branch].present?
  end

  def show
    @session = AgentSession.where(project: accessible_projects).find(params[:id])
    @events = @session.run_events.order(occurred_at: :asc)
    @passport = @session.run_passport
  end
end
