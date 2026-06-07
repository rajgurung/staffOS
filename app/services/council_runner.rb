class CouncilRunner
  REVIEW_ORDER = %w[staff_engineer sre security product_manager devils_advocate writing_coach].freeze

  def initialize(passport)
    @passport = passport
  end

  def run!
    REVIEW_ORDER.each do |persona|
      review = @passport.council_reviews.find_or_initialize_by(persona: persona)
      review.update!(status: "running")

      result = generate_review(persona)

      review.update!(
        status: "completed",
        findings: result[:findings],
        recommendation: result[:recommendation],
        risk_assessment: result[:risk_assessment],
        score: result[:score],
        completed_at: Time.current
      )
    end

    @passport.council_reviews.ordered
  end

  def run_persona!(persona)
    review = @passport.council_reviews.find_or_initialize_by(persona: persona)
    review.update!(status: "running")

    result = generate_review(persona)

    review.update!(
      status: "completed",
      findings: result[:findings],
      recommendation: result[:recommendation],
      risk_assessment: result[:risk_assessment],
      score: result[:score],
      completed_at: Time.current
    )

    review
  end

  private

  def generate_review(persona)
    send(:"review_as_#{persona}")
  end

  def review_as_staff_engineer
    files = @passport.files_touched || []
    test_summary = @passport.test_summary || {}
    findings = []

    service_files = files.select { |f| f["path"].to_s.match?(/service|handler|processor/i) }
    if service_files.any?
      findings << { type: "architecture", severity: "medium", detail: "#{service_files.count} service-layer files modified. Verify separation of concerns is maintained." }
    end

    if files.any? { |f| f["additions"].to_i > 50 }
      findings << { type: "complexity", severity: "medium", detail: "Large changes detected. Consider breaking into smaller, focused commits." }
    end

    unless files.any? { |f| f["path"].to_s.match?(/spec|test/i) }
      findings << { type: "testing", severity: "high", detail: "No test files modified. Behavioural changes should have corresponding tests." }
    end

    if @passport.intent.to_s.match?(/retry|backoff|queue|async/i)
      findings << { type: "resilience", severity: "medium", detail: "Retry/async logic detected. Verify idempotency, timeouts, and circuit breaker patterns." }
    end

    total_changes = files.sum { |f| f["additions"].to_i + f["deletions"].to_i }
    score = 8.0
    score -= 1.0 if findings.any? { |f| f[:severity] == "high" }
    score -= 0.5 * findings.count { |f| f[:severity] == "medium" }
    score = [score, 1.0].max

    {
      findings: findings,
      recommendation: findings.empty? ? "Clean implementation. Approve with standard review." : "Address #{findings.count} finding(s) before merge. Focus on #{findings.first[:type]} concerns.",
      risk_assessment: "#{total_changes} lines changed across #{files.count} files. #{test_summary['status'] == 'passed' ? 'Tests passing.' : 'Test status unclear.'}",
      score: score
    }
  end

  def review_as_sre
    files = @passport.files_touched || []
    findings = []

    config_files = files.select { |f| f["path"].to_s.match?(/config|initializer|\.yml|\.yaml|\.env/i) }
    if config_files.any?
      findings << { type: "configuration", severity: "high", detail: "#{config_files.count} config file(s) changed: #{config_files.map { |f| f['path'] }.join(', ')}. Verify staging deployment first." }
    end

    if @passport.intent.to_s.match?(/retry|timeout|backoff|circuit/i)
      findings << { type: "observability", severity: "medium", detail: "Retry/timeout logic changed. Ensure metrics, alerts, and structured logging cover the new behaviour." }
    end

    unless files.any? { |f| f["path"].to_s.match?(/log|monitor|metric|instrument/i) }
      findings << { type: "observability", severity: "medium", detail: "No observability files touched. Verify new behaviour is visible in dashboards and alerts." }
    end

    if files.any? { |f| f["path"].to_s.match?(/migration|schema/i) }
      findings << { type: "database", severity: "high", detail: "Database migration detected. Verify rollback plan and zero-downtime compatibility." }
    end

    score = 8.0
    score -= 1.5 * findings.count { |f| f[:severity] == "high" }
    score -= 0.5 * findings.count { |f| f[:severity] == "medium" }
    score = [score, 1.0].max

    {
      findings: findings,
      recommendation: findings.empty? ? "No operational concerns. Safe to deploy." : "#{findings.count} operational concern(s). #{findings.any? { |f| f[:severity] == 'high' } ? 'Staging deployment recommended before production.' : 'Monitor closely after deploy.'}",
      risk_assessment: "Operational risk: #{findings.any? { |f| f[:severity] == 'high' } ? 'elevated' : 'standard'}. #{config_files&.any? ? 'Config changes require careful rollout.' : 'No config changes.'}",
      score: score
    }
  end

  def review_as_security
    files = @passport.files_touched || []
    findings = []

    auth_files = files.select { |f| f["path"].to_s.match?(/auth|session|token|permission|policy|credential|secret/i) }
    if auth_files.any?
      findings << { type: "authentication", severity: "critical", detail: "Auth-sensitive files modified: #{auth_files.map { |f| f['path'] }.join(', ')}. Requires security review." }
    end

    if files.any? { |f| f["path"].to_s.match?(/controller|api|endpoint|route/i) }
      findings << { type: "api_surface", severity: "medium", detail: "API surface modified. Verify authorization checks on all new/changed endpoints." }
    end

    if files.any? { |f| f["path"].to_s.match?(/Gemfile|package\.json|yarn\.lock|Gemfile\.lock/i) }
      findings << { type: "dependencies", severity: "medium", detail: "Dependency files changed. Run vulnerability scan (bundler-audit / npm audit)." }
    end

    payment_files = files.select { |f| f["path"].to_s.match?(/payment|billing|stripe|charge|invoice/i) }
    if payment_files.any?
      findings << { type: "payment", severity: "critical", detail: "Payment-related files modified. Requires PCI compliance review." }
    end

    score = 9.0
    score -= 3.0 * findings.count { |f| f[:severity] == "critical" }
    score -= 1.0 * findings.count { |f| f[:severity] == "medium" }
    score = [score, 1.0].max

    {
      findings: findings,
      recommendation: findings.empty? ? "No security concerns identified. Standard review sufficient." : "#{findings.count} security concern(s). #{findings.any? { |f| f[:severity] == 'critical' } ? 'REQUIRES dedicated security review before merge.' : 'Standard security checklist applies.'}",
      risk_assessment: "Security posture: #{findings.any? { |f| f[:severity] == 'critical' } ? 'HIGH RISK - auth/payment surface affected' : 'standard'}.",
      score: score
    }
  end

  def review_as_product_manager
    files = @passport.files_touched || []
    test_summary = @passport.test_summary || {}
    findings = []

    if @passport.intent.blank?
      findings << { type: "clarity", severity: "medium", detail: "No clear intent captured. Difficult to verify change aligns with product requirements." }
    end

    ui_files = files.select { |f| f["path"].to_s.match?(/view|template|component|frontend|css|scss/i) }
    if ui_files.any?
      findings << { type: "user_impact", severity: "low", detail: "#{ui_files.count} UI file(s) changed. Verify visual regression and UX consistency." }
    end

    api_files = files.select { |f| f["path"].to_s.match?(/controller|api|serializer/i) }
    if api_files.any?
      findings << { type: "api_contract", severity: "medium", detail: "API contract may be affected. Check backward compatibility for consumers." }
    end

    if test_summary["status"] == "passed" && test_summary["new_tests"].to_i > 0
      findings << { type: "coverage", severity: "positive", detail: "#{test_summary['new_tests']} new tests added. Good coverage of new behaviour." }
    end

    score = 7.5
    score += 0.5 if findings.any? { |f| f[:severity] == "positive" }
    score -= 0.5 * findings.count { |f| f[:severity] == "medium" }
    score = [score, 1.0].max.round(1)

    {
      findings: findings,
      recommendation: "Changes appear #{@passport.intent.present? ? 'aligned with stated intent' : 'functional but intent unclear'}. #{ui_files&.any? ? 'QA visual check recommended.' : 'No UI impact.'}",
      risk_assessment: "Product risk: low. #{api_files&.any? ? 'API changes need consumer verification.' : 'No API contract changes.'}",
      score: score
    }
  end

  def review_as_devils_advocate
    files = @passport.files_touched || []
    findings = []

    findings << { type: "assumptions", severity: "medium", detail: "What happens if the external provider is completely down, not just returning errors? Is there a fallback path?" }

    if @passport.intent.to_s.match?(/retry|backoff/i)
      findings << { type: "edge_case", severity: "medium", detail: "Retry logic can mask underlying issues. Are you sure the root cause isn't being hidden by retries?" }
      findings << { type: "resource", severity: "medium", detail: "What's the maximum resource consumption under sustained retry? Could this cause cascading failures?" }
    end

    if files.count > 5
      findings << { type: "scope", severity: "low", detail: "#{files.count} files changed in one session. Could this be broken into smaller, independently deployable changes?" }
    end

    findings << { type: "rollback", severity: "medium", detail: "What's the rollback plan if this change causes issues in production? Is it a clean revert?" }

    score = 6.5

    {
      findings: findings,
      recommendation: "Challenge the assumptions. #{findings.count} question(s) raised. Not blockers, but worth discussing before merge.",
      risk_assessment: "Playing devil's advocate on #{files.count} file changes. Key concern: failure mode coverage and rollback safety.",
      score: score
    }
  end

  def review_as_writing_coach
    findings = []

    if @passport.intent.present?
      if @passport.intent.length < 20
        findings << { type: "intent_clarity", severity: "medium", detail: "Intent is too brief. Add context about why this change is needed, not just what." }
      else
        findings << { type: "intent_clarity", severity: "positive", detail: "Clear intent provided. Good for future context and onboarding." }
      end
    else
      findings << { type: "intent_clarity", severity: "high", detail: "No intent captured. Future engineers won't understand why this change was made." }
    end

    if @passport.summary.present? && @passport.summary.length > 50
      findings << { type: "summary", severity: "positive", detail: "Good summary captured. Consider saving as PR description." }
    end

    missing = @passport.missing_checks || []
    if missing.any? { |c| c["check"].to_s.match?(/ADR|decision/i) }
      findings << { type: "documentation", severity: "medium", detail: "Architecture decision detected but no ADR exists. Document the rationale for future reference." }
    end

    findings << { type: "pr_description", severity: "low", detail: "Generate a PR summary from the passport to ensure reviewers have full context." }

    score = 7.0
    score += 0.5 * findings.count { |f| f[:severity] == "positive" }
    score -= 0.5 * findings.count { |f| f[:severity] == "high" }
    score = [score, 1.0].max.round(1)

    {
      findings: findings,
      recommendation: "Documentation #{findings.any? { |f| f[:severity] == 'high' } ? 'needs improvement' : 'is adequate'}. #{findings.any? { |f| f[:type] == 'documentation' } ? 'Consider creating an ADR.' : 'Good documentation coverage.'}",
      risk_assessment: "Documentation debt: #{findings.count { |f| %w[medium high].include?(f[:severity]) }} item(s) to address.",
      score: score
    }
  end
end
