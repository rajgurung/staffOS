class SearchController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    return if @query.blank? || current_project.nil?

    q = "%#{@query}%"
    @passports = current_project.run_passports.where("intent ILIKE :q OR summary ILIKE :q", q: q).limit(10)
    @documents = current_project.documents.where("title ILIKE :q OR content_markdown ILIKE :q", q: q).limit(10)
    @decisions = current_project.decision_logs.where("title ILIKE :q OR decision ILIKE :q OR context ILIKE :q", q: q).limit(10)
    @memory_items = current_project.memory_items.where("content ILIKE :q", q: q).limit(10)
    @sessions = current_project.agent_sessions.where("branch_name ILIKE :q OR agent_name ILIKE :q", q: q).limit(10)

    @total = [@passports, @documents, @decisions, @memory_items, @sessions].sum(&:count)
  end
end
