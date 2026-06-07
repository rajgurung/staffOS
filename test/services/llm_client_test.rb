require "test_helper"

class LlmClientTest < ActiveSupport::TestCase
  test "is disabled when no API key is configured" do
    with_env("ANTHROPIC_API_KEY" => nil) do
      skip "credentials carry an Anthropic key in this environment" if LlmClient.api_key.present?
      assert_not LlmClient.enabled?
      assert_nil LlmClient.new.complete(system: "s", prompt: "p")
    end
  end

  test "is enabled when an API key is present in the environment" do
    with_env("ANTHROPIC_API_KEY" => "sk-test") do
      assert LlmClient.enabled?
      assert_equal "sk-test", LlmClient.api_key
    end
  end

  test "summary mode uses a cheaper model than council mode" do
    summary = LlmClient::PRICING.fetch(LlmClient::SUMMARY_MODEL)
    council = LlmClient::PRICING.fetch(LlmClient::COUNCIL_MODEL)
    assert_operator summary[:input], :<, council[:input]
    assert_operator summary[:output], :<, council[:output]
  end

  test "cost is computed from token usage and model pricing" do
    client = LlmClient.new(model: "claude-opus-4-8")
    # 1M input @ $5 + 1M output @ $25 = $30.00 = 3000 cents
    cents = client.send(:cost_cents, 1_000_000, 1_000_000)
    assert_equal 3000, cents
  end

  private

  def with_env(values)
    original = values.transform_values { |_| nil }
    values.each_key { |k| original[k] = ENV[k] }
    values.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
