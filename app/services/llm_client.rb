# Thin wrapper around the official Anthropic SDK.
#
# StaffOS keeps source code local by default (see SPEC §17), so the only thing
# we ever send is passport metadata — file paths, categories, test summaries,
# risk signals — never file contents. Every call returns a Result carrying the
# text plus token usage and computed cost so the caller can record AI spend.
#
# The client degrades gracefully: when no API key is configured (the common
# case in development, CI, and seeding) `enabled?` is false and callers fall
# back to deterministic heuristics. A failed network call surfaces as a nil
# result rather than an exception, so a passport is never blocked on the LLM.
class LlmClient
  # $ per 1M tokens, mirrored from the model catalog. Used to estimate cost.
  PRICING = {
    "claude-opus-4-8"   => { input: 5.0,  output: 25.0 },
    "claude-sonnet-4-6" => { input: 3.0,  output: 15.0 },
    "claude-haiku-4-5"  => { input: 1.0,  output: 5.0 }
  }.freeze

  # Cheaper model for smart-summary mode; capable model for council reviews.
  SUMMARY_MODEL = ENV.fetch("STAFFOS_SUMMARY_MODEL", "claude-haiku-4-5")
  COUNCIL_MODEL = ENV.fetch("STAFFOS_COUNCIL_MODEL", "claude-opus-4-8")

  Result = Struct.new(:text, :model, :input_tokens, :output_tokens, :cost_cents, keyword_init: true)

  class << self
    def enabled?
      api_key.present?
    end

    def api_key
      ENV["ANTHROPIC_API_KEY"].presence ||
        Rails.application.credentials.dig(:anthropic, :api_key)
    end
  end

  def initialize(model: SUMMARY_MODEL)
    @model = model
  end

  def enabled?
    self.class.enabled?
  end

  # Returns a Result, or nil if the client is disabled or the call fails.
  # When +schema+ is given, the response is constrained to that JSON schema
  # and the parsed Hash is returned instead of raw text.
  def complete(system:, prompt:, max_tokens: 2000, schema: nil)
    return nil unless enabled?

    params = {
      model: @model,
      max_tokens: max_tokens,
      system_: [{ type: "text", text: system }],
      messages: [{ role: "user", content: prompt }]
    }
    params[:output_config] = { format: { type: "json_schema", schema: schema } } if schema

    message = client.messages.create(**params)
    build_result(message, schema)
  rescue => e
    Rails.logger.warn("[LlmClient] call failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def client
    @client ||= Anthropic::Client.new(api_key: self.class.api_key)
  end

  def build_result(message, schema)
    text = message.content.filter_map { |b| b.text if b.type == :text }.join
    usage = message.usage
    input_tokens = usage&.input_tokens.to_i
    output_tokens = usage&.output_tokens.to_i

    Result.new(
      text: schema ? parse_json(text) : text,
      model: @model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cost_cents: cost_cents(input_tokens, output_tokens)
    )
  end

  def parse_json(text)
    JSON.parse(text)
  rescue JSON::ParserError
    nil
  end

  def cost_cents(input_tokens, output_tokens)
    rates = PRICING[@model] || PRICING[COUNCIL_MODEL]
    dollars = (input_tokens / 1_000_000.0 * rates[:input]) +
              (output_tokens / 1_000_000.0 * rates[:output])
    (dollars * 100).round
  end
end
