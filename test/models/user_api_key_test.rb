require "test_helper"

class UserApiKeyTest < ActiveSupport::TestCase
  test "anthropic key is encrypted at rest and round-trips" do
    user = User.create!(email: "keyed@example.com", password: "password123")
    user.update!(anthropic_api_key: "sk-ant-test-abc123xyz9")

    assert_equal "sk-ant-test-abc123xyz9", user.reload.anthropic_api_key
    raw = ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql(["SELECT anthropic_api_key FROM users WHERE id = ?", user.id])
    )
    refute_includes raw.to_s, "abc123xyz9", "key must not be stored in plaintext"
    assert_equal "sk-ant-…xyz9", user.anthropic_key_hint
  end

  test "rejects keys that do not look like Anthropic keys" do
    user = User.create!(email: "badkey@example.com", password: "password123")
    refute user.update(anthropic_api_key: "sk-proj-openai-lol")
    assert user.update(anthropic_api_key: "")
  end

  test "key_for prefers the user's own key over the server fallback" do
    user = User.create!(email: "own@example.com", password: "password123")
    user.update!(anthropic_api_key: "sk-ant-own-key-0001")
    assert_equal "sk-ant-own-key-0001", LlmClient.key_for(user)
    assert LlmClient.enabled_for?(user)

    keyless = User.create!(email: "keyless@example.com", password: "password123")
    # No personal key → falls back to the server key (nil when unset, as in CI)
    if LlmClient.api_key.nil?
      assert_nil LlmClient.key_for(keyless)
    else
      assert_equal LlmClient.api_key, LlmClient.key_for(keyless)
    end
  end
end
