module ProjectsHelper
  def hook_config_json(project)
    token = project.api_tokens.first&.token
    headers = { "X-StaffOS-Project" => project.name }
    headers["Authorization"] = "Bearer #{token}" if token

    config = {
      hooks: {
        SessionStart: [{
          hooks: [{
            type: "http",
            url: "http://localhost:9090/api/v1/hooks/session_start",
            headers: headers,
            timeout: 10
          }]
        }],
        UserPromptSubmit: [{
          hooks: [{
            type: "http",
            url: "http://localhost:9090/api/v1/hooks/prompt",
            headers: headers,
            timeout: 10
          }]
        }],
        PostToolUse: [{
          matcher: "Bash|Edit|Write|Read",
          hooks: [{
            type: "http",
            url: "http://localhost:9090/api/v1/hooks/post_tool",
            headers: headers,
            timeout: 10
          }]
        }],
        Stop: [{
          hooks: [{
            type: "http",
            url: "http://localhost:9090/api/v1/hooks/stop",
            headers: headers,
            timeout: 30
          }]
        }]
      }
    }
    JSON.pretty_generate(config)
  end
end
