class DashboardController < ApplicationController
  def index
    return unless current_project

    sessions = current_project.agent_sessions
    passports = current_project.run_passports

    @total_runs = sessions.count
    @total_passports = passports.count
    @review_required = passports.where(human_review_required: true).count
    @active_runs = sessions.where(status: "active").order(started_at: :desc).limit(5)
    @recent_passports = passports.includes(:agent_session).order(created_at: :desc).limit(5)
    @recent_events = RunEvent.joins(:agent_session).where(agent_sessions: { project_id: current_project.id }).order(occurred_at: :desc).limit(12)

    @high_risk = passports.where(risk_level: "High").count
    @medium_risk = passports.where(risk_level: "Medium").count
    @low_risk = passports.where(risk_level: "Low").count
    @avg_readiness = passports.average(:readiness_score)&.round(0) || 0

    @total_tokens = sessions.sum { |s| s.metadata&.dig("tokens_used").to_i }
    @estimated_cost = (@total_tokens / 1_000_000.0 * 3.0).round(2) # rough estimate at $3/MTok

    @active_workstreams = current_project.workstreams.active.recent.limit(5)
    @recent_documents = current_project.documents.order(created_at: :desc).limit(3)
    @recent_decisions = current_project.decision_logs.order(created_at: :desc).limit(3)
  end
end
