class RunPassportsController < ApplicationController
  before_action :set_passport, only: [:show, :run_council, :generate_document, :export, :set_review_mode]

  def index
    @passports = RunPassport.order(created_at: :desc)
  end

  def show
    @events = @passport.agent_session&.run_events&.order(occurred_at: :asc) || []
    @council_reviews = @passport.council_reviews.ordered
  end

  def run_council
    CouncilRunner.new(@passport).run!
    redirect_to run_passport_path(@passport, anchor: "council"), notice: "AI Council review completed."
  end

  def set_review_mode
    @passport.update!(review_mode: params[:mode])
    if params[:mode] == "full_council"
      CouncilRunner.new(@passport).run!
      redirect_to run_passport_path(@passport, anchor: "council"), notice: "Full Council review started."
    else
      redirect_to run_passport_path(@passport), notice: "Review mode set to #{@passport.review_mode_label}."
    end
  end

  def generate_document
    generator = DocumentGenerator.new(@passport)
    case params[:doc_type]
    when "adr"
      doc = generator.generate_adr!
      redirect_to document_path(doc), notice: "ADR draft generated."
    when "decision_log"
      log = generator.generate_decision_log!
      redirect_to decision_log_path(log), notice: "Decision log generated."
    when "pr_summary"
      doc = generator.generate_pr_summary!
      redirect_to document_path(doc), notice: "PR summary generated."
    when "memory"
      generator.generate_memory_item!
      redirect_to memory_items_path, notice: "Memory item saved."
    else
      redirect_to run_passport_path(@passport), alert: "Unknown document type."
    end
  end

  def export
    respond_to do |format|
      format.json { render json: passport_json }
      format.any do
        send_data passport_markdown, filename: "passport-#{@passport.id}.md", type: "text/markdown"
      end
    end
  end

  private

  def set_passport
    @passport = RunPassport.find(params[:id])
  end

  def passport_json
    {
      id: @passport.id,
      intent: @passport.intent,
      summary: @passport.summary,
      risk_level: @passport.risk_level,
      readiness_score: @passport.readiness_score,
      human_review_required: @passport.human_review_required,
      test_summary: @passport.test_summary,
      files_touched: @passport.files_touched,
      missing_checks: @passport.missing_checks,
      recommended_actions: @passport.recommended_actions,
      agent: @passport.agent_session.agent_name,
      branch: @passport.agent_session.branch_name,
      created_at: @passport.created_at
    }
  end

  def passport_markdown
    <<~MD
      # Run Passport ##{@passport.id}

      **Intent:** #{@passport.intent}
      **Agent:** #{@passport.agent_session.agent_name}
      **Branch:** #{@passport.agent_session.branch_name}
      **Risk Level:** #{@passport.risk_level}
      **Readiness:** #{@passport.readiness_score}%
      **Human Review:** #{@passport.human_review_required? ? 'Required' : 'Not required'}

      ## Summary

      #{@passport.summary}

      ## Files Touched

      #{(@passport.files_touched || []).map { |f| "- `#{f['path']}` (+#{f['additions']}, -#{f['deletions']})" }.join("\n")}

      ## Test Evidence

      #{@passport.test_summary.present? ? "Status: #{@passport.test_summary['status']}, Total: #{@passport.test_summary['total']}, Failed: #{@passport.test_summary['failed']}" : "No test evidence captured."}

      ## Missing Checks

      #{(@passport.missing_checks || []).map { |c| "- [#{c['severity'].upcase}] #{c['check']}" }.join("\n").presence || "None"}

      ## Recommended Actions

      #{(@passport.recommended_actions || []).map { |a| "- [ ] #{a['action']} (#{a['priority']})" }.join("\n").presence || "None"}
    MD
  end
end
