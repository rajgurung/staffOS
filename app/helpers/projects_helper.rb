module ProjectsHelper
  def hook_config_json(project)
    config = {
      hooks: {
        SessionStart: [{
          type: "command",
          command: "curl -s -X POST http://localhost:9090/api/v1/events -H 'Content-Type: application/json' -d '{\"session_id\": \"$CLAUDE_SESSION_ID\", \"event_type\": \"session_started\", \"project_name\": \"#{project.name}\", \"provider\": \"claude_code\"}'"
        }],
        UserPromptSubmit: [{
          type: "command",
          command: "curl -s -X POST http://localhost:9090/api/v1/events -H 'Content-Type: application/json' -d '{\"session_id\": \"$CLAUDE_SESSION_ID\", \"event_type\": \"prompt_submitted\", \"payload\": {\"prompt\": \"$CLAUDE_USER_PROMPT\"}}'"
        }],
        Stop: [{
          type: "command",
          command: "curl -s -X POST http://localhost:9090/api/v1/events -H 'Content-Type: application/json' -d '{\"session_id\": \"$CLAUDE_SESSION_ID\", \"event_type\": \"session_completed\"}'"
        }]
      }
    }
    JSON.pretty_generate(config)
  end
end
