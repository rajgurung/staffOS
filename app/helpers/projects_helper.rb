module ProjectsHelper
  # Mirrors what `staffos init` / `staffos hook` install. Command hooks, not
  # HTTP: `staffos capture` adds the local git branch, which the server can't
  # work out, and without it events can't be filed under a branch passport.
  # The token isn't here; capture reads it from the repo's .staffos.yml.
  HOOK_EVENTS = {
    "SessionStart" => "session_start",
    "UserPromptSubmit" => "prompt",
    "PreToolUse" => "pre_tool",
    "PostToolUse" => "post_tool",
    "Stop" => "stop"
  }.freeze

  def hook_config_json
    hooks = HOOK_EVENTS.to_h do |claude_event, api_event|
      entry = { "hooks" => [{ "type" => "command", "command" => "staffos capture #{api_event}" }] }
      entry["matcher"] = "Bash|Edit|Write|Read" if %w[PreToolUse PostToolUse].include?(claude_event)
      [claude_event, [entry]]
    end
    JSON.pretty_generate({ "hooks" => hooks })
  end
end
