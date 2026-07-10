class RiskCockpitController < ApplicationController
  before_action :require_current_project, only: :index

  def index
    @passports = current_project.run_passports.includes(:agent_session).order(created_at: :desc)
    @total_runs = @passports.count
    @high_risk = @passports.where(risk_level: "High").count
    @medium_risk = @passports.where(risk_level: "Medium").count
    @low_risk = @passports.where(risk_level: "Low").count
    @review_required = @passports.where(human_review_required: true).count
    @avg_readiness = @passports.average(:readiness_score)&.round(0) || 0

    @high_risk_files = extract_high_risk_files
    @recent_passports = @passports.limit(10)
  end

  private

  def extract_high_risk_files
    files = {}
    @passports.each do |passport|
      (passport.files_touched || []).each do |file|
        path = file["path"]
        next unless path
        files[path] ||= { count: 0, total_changes: 0 }
        files[path][:count] += 1
        files[path][:total_changes] += file["additions"].to_i + file["deletions"].to_i
      end
    end
    files.sort_by { |_, v| -v[:count] }.first(10).to_h
  end
end
