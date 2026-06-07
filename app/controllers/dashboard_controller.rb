class DashboardController < ApplicationController
  def index
    @total_runs = AgentSession.count
    @total_passports = RunPassport.count
    @review_required = RunPassport.where(human_review_required: true).count
    @active_runs = AgentSession.where(status: "active").includes(:project).order(started_at: :desc).limit(5)
    @recent_passports = RunPassport.includes(agent_session: :project).order(created_at: :desc).limit(5)
    @recent_events = RunEvent.includes(agent_session: :project).order(occurred_at: :desc).limit(12)

    passports = RunPassport.all
    @high_risk = passports.where(risk_level: "High").count
    @medium_risk = passports.where(risk_level: "Medium").count
    @low_risk = passports.where(risk_level: "Low").count
    @avg_readiness = passports.average(:readiness_score)&.round(0) || 0

    @recent_documents = Document.order(created_at: :desc).limit(3)
    @recent_decisions = DecisionLog.order(created_at: :desc).limit(3)
  end
end
