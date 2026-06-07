class SearchController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    return if @query.blank?

    @passports = RunPassport.where("intent ILIKE :q OR summary ILIKE :q", q: "%#{@query}%").limit(10)
    @documents = Document.where("title ILIKE :q OR content_markdown ILIKE :q", q: "%#{@query}%").limit(10)
    @decisions = DecisionLog.where("title ILIKE :q OR decision ILIKE :q OR context ILIKE :q", q: "%#{@query}%").limit(10)
    @memory_items = MemoryItem.where("content ILIKE :q", q: "%#{@query}%").limit(10)
    @sessions = AgentSession.where("branch_name ILIKE :q OR agent_name ILIKE :q", q: "%#{@query}%").limit(10)

    @total = [@passports, @documents, @decisions, @memory_items, @sessions].sum(&:count)
  end
end
