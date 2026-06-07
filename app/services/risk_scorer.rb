class RiskScorer
  HIGH_RISK_PATTERNS = %w[
    auth permission session token
    payment billing stripe charge invoice
    deploy infra terraform docker kubernetes
    .github/workflows ci cd pipeline
    migration schema
    credentials secrets .env
  ].freeze

  MEDIUM_RISK_PATTERNS = %w[
    retry backoff queue worker job
    config initializer
    api controller endpoint
    cache redis
    Gemfile package.json yarn.lock
  ].freeze

  def initialize(passport)
    @passport = passport
  end

  def score
    signals = gather_signals
    level = compute_level(signals)
    numeric = compute_numeric_score(signals)

    {
      level: level,
      score: numeric,
      signals: signals,
      human_review_required: level != "Low"
    }
  end

  private

  def gather_signals
    signals = []
    files = @passport.files_touched || []

    files.each do |file|
      path = file["path"].to_s.downcase

      HIGH_RISK_PATTERNS.each do |pattern|
        if path.include?(pattern)
          signals << { file: file["path"], risk: "high", reason: "Matches high-risk pattern: #{pattern}" }
        end
      end

      MEDIUM_RISK_PATTERNS.each do |pattern|
        if path.include?(pattern)
          signals << { file: file["path"], risk: "medium", reason: "Matches medium-risk pattern: #{pattern}" }
        end
      end
    end

    test_summary = @passport.test_summary || {}
    if test_summary.empty? || test_summary["status"].nil?
      signals << { check: "tests_not_run", risk: "high", reason: "No test evidence found" }
    elsif test_summary["failed"].to_i > 0
      signals << { check: "tests_failing", risk: "high", reason: "#{test_summary['failed']} test(s) failing" }
    end

    # "Behavioural change without tests" is a warning (SPEC §15). Documentation
    # and test files don't themselves require accompanying tests, so a docs-only
    # or test-only change stays Low.
    changed_files = files.select { |f| f["additions"].to_i > 0 || f["deletions"].to_i > 0 }
    test_files = changed_files.select { |f| f["path"].to_s.match?(/spec|test/i) }
    code_files = changed_files.reject { |f| f["path"].to_s.match?(/spec|test|\.md\z|\Adocs\/|readme/i) }
    if code_files.any? && test_files.empty?
      signals << { check: "no_test_changes", risk: "medium", reason: "Code changed but no test files modified" }
    end

    signals.uniq { |s| [s[:file], s[:check], s[:reason]] }
  end

  def compute_level(signals)
    return "High" if signals.any? { |s| s[:risk] == "high" }
    return "Medium" if signals.any? { |s| s[:risk] == "medium" }
    "Low"
  end

  def compute_numeric_score(signals)
    base = 3.0
    signals.each do |s|
      case s[:risk]
      when "high" then base += 2.5
      when "medium" then base += 1.2
      end
    end
    [base, 10.0].min.round(1)
  end
end
