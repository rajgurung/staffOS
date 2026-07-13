class DocumentGenerator
  def initialize(passport)
    @passport = passport
    @project = passport.project
  end

  def generate_adr!
    Document.create!(
      project: @project,
      run_passport: @passport,
      document_type: "adr",
      status: "draft",
      title: "ADR: #{extract_topic}",
      content_markdown: adr_content
    )
  end

  def generate_decision_log!
    DecisionLog.create!(
      project: @project,
      run_passport: @passport,
      status: "draft",
      title: "Decision: #{extract_topic}",
      context: "During AI-assisted work on branch #{@passport.workstream.branch_name}, " \
               "the following change was made: #{@passport.intent}",
      decision: @passport.summary.to_s.split(".").first.to_s + ".",
      rationale: "Identified during automated code review. #{@passport.risk_level} risk level. " \
                 "#{@passport.test_summary&.dig('status') == 'passed' ? 'All tests passing.' : 'Test status needs verification.'}",
      consequences: (@passport.missing_checks || []).map { |c| c["check"] }.join(". ").presence || "No significant consequences identified."
    )
  end

  def generate_pr_summary!
    Document.create!(
      project: @project,
      run_passport: @passport,
      document_type: "pr_summary",
      status: "draft",
      title: "PR: #{extract_topic}",
      content_markdown: pr_summary_content
    )
  end

  def generate_memory_item!
    MemoryItem.create!(
      project: @project,
      memory_type: "decision",
      content: @passport.summary.to_s.split(".").first.to_s + ".",
      confidence: @passport.readiness_score.to_f / 100
    )
  end

  private

  def extract_topic
    intent = @passport.intent.to_s
    intent.length > 60 ? intent[0..57] + "..." : intent
  end

  def adr_content
    <<~MD
      ## Status

      Proposed

      ## Context

      #{@passport.intent}

      This change was made during AI-assisted work on branch `#{@passport.workstream.branch_name}` across #{@passport.sessions_count} captured sessions.

      ## Decision

      #{@passport.summary}

      ## Files Changed

      #{(@passport.files_touched || []).map { |f| "- `#{f['path']}` (+#{f['additions']}, -#{f['deletions']})" }.join("\n")}

      ## Risk Assessment

      - Risk Level: **#{@passport.risk_level}**
      - Readiness Score: **#{@passport.readiness_score}%**
      - Human Review Required: **#{@passport.human_review_required? ? 'Yes' : 'No'}**

      ## Consequences

      #{(@passport.missing_checks || []).map { |c| "- #{c['check']} (#{c['severity']})" }.join("\n").presence || "No significant consequences identified."}

      ## Follow-up Actions

      #{(@passport.recommended_actions || []).map { |a| "- [ ] #{a['action']} (#{a['priority']})" }.join("\n").presence || "None identified."}
    MD
  end

  def pr_summary_content
    test_info = if @passport.test_summary.present?
      "#{@passport.test_summary['total']} tests, #{@passport.test_summary['failed']} failures"
    else
      "Tests not run"
    end

    <<~MD
      ## Summary

      #{@passport.summary}

      ## Changes

      #{(@passport.files_touched || []).map { |f| "- `#{f['path']}` (+#{f['additions']}, -#{f['deletions']})" }.join("\n")}

      ## Test Evidence

      - Status: **#{@passport.test_summary&.dig('status')&.capitalize || 'Unknown'}**
      - #{test_info}

      ## Risk

      - Level: **#{@passport.risk_level}**
      - Readiness: **#{@passport.readiness_score}%**

      ## Checklist

      #{(@passport.recommended_actions || []).map { |a| "- [ ] #{a['action']}" }.join("\n")}
    MD
  end
end
