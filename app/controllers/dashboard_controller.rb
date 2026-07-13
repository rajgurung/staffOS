class DashboardController < ApplicationController
  before_action :require_current_project, only: :index

  def index
    sessions = current_project.agent_sessions.where.not(status: "noise")
    passports = current_project.run_passports

    @total_runs = sessions.count
    @total_passports = passports.count
    @review_required = passports.where(human_review_required: true).count
    @active_runs = sessions.where(status: "active").order(started_at: :desc).limit(5)
    @recent_passports = passports.includes(:workstream).order(created_at: :desc).limit(5)
    @recent_events = RunEvent.joins(:agent_session)
      .where(agent_sessions: { project_id: current_project.id })
      .where.not(agent_sessions: { status: "noise" })
      .order(occurred_at: :desc).limit(12)

    @high_risk = passports.where(risk_level: "High").count
    @medium_risk = passports.where(risk_level: "Medium").count
    @low_risk = passports.where(risk_level: "Low").count
    @avg_readiness = passports.average(:readiness_score)&.round(0) || 0

    # Real LLM spend captured from smart summaries and council reviews, plus any
    # token counts reported by the agent itself via session metadata.
    llm_tokens = passports.sum(:input_tokens) + passports.sum(:output_tokens)
    agent_tokens = sessions.sum { |s| s.metadata&.dig("tokens_used").to_i }
    @total_tokens = llm_tokens + agent_tokens
    @estimated_cost = (passports.sum(:cost_cents) / 100.0).round(2)

    @active_workstreams = current_project.workstreams.active.recent.limit(5)
    @recent_documents = current_project.documents.order(created_at: :desc).limit(3)
    @recent_decisions = current_project.decision_logs.order(created_at: :desc).limit(3)
  end
end
