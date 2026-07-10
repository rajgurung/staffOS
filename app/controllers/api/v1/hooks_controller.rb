module Api
  module V1
    class HooksController < Api::BaseController
      # Claude Code HTTP hooks POST the full event context as JSON.
      # Each hook receives: session_id, cwd, hook_event_name, permission_mode,
      # plus event-specific fields (tool_name, tool_input, prompt, etc.)

      def session_start
        ws = resolve_workstream
        session = find_or_create_session

        session.run_events.create!(
          event_type: "session_started",
          occurred_at: Time.current,
          workstream: ws,
          source: "claude_code",
          payload: {
            model: params[:model],
            source: params[:source],
            cwd: params[:cwd],
            permission_mode: params[:permission_mode]
          }.compact
        )

        render json: {
          hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: "StaffOS is capturing this session. Project: #{project_name}. Branch: #{current_branch}."
          }
        }
      end

      def prompt
        ws = resolve_workstream
        session = find_or_create_session

        session.run_events.create!(
          event_type: "prompt_submitted",
          occurred_at: Time.current,
          workstream: ws,
          source: "claude_code",
          payload: { prompt: params[:prompt] }.compact
        )

        render json: {}
      end

      def pre_tool
        # Log the tool use intent (before execution)
        ws = resolve_workstream
        session = find_or_create_session

        tool = params[:tool_name]
        input = params[:tool_input] || {}

        event_type = case tool
        when "Read" then "file_read"
        when "Edit", "Write" then "file_edit_intent"
        when "Bash" then "command_intent"
        else "tool_intent"
        end

        session.run_events.create!(
          event_type: event_type,
          occurred_at: Time.current,
          workstream: ws,
          source: "claude_code",
          payload: {
            tool_name: tool,
            file: input["file_path"],
            command: input["command"],
            tool_input: input
          }.compact
        )

        render json: {}
      end

      def post_tool
        ws = resolve_workstream
        session = find_or_create_session

        tool = params[:tool_name]
        input = params[:tool_input] || {}
        output = params[:tool_output]

        event_type = case tool
        when "Read" then "file_read"
        when "Edit", "Write" then "file_edited"
        when "Bash" then "command_run"
        else "tool_completed"
        end

        payload = { tool_name: tool }.compact

        case tool
        when "Read"
          payload[:file] = input["file_path"]
          payload[:lines] = output.to_s.lines.count if output
        when "Edit", "Write"
          payload[:file] = input["file_path"]
          if input["old_string"] && input["new_string"]
            payload[:additions] = input["new_string"].to_s.lines.count
            payload[:deletions] = input["old_string"].to_s.lines.count
          end
        when "Bash"
          payload[:command] = input["command"]
          payload[:exit_code] = output.to_s.match?(/exit code/i) ? 1 : 0
        end

        session.run_events.create!(
          event_type: event_type,
          occurred_at: Time.current,
          workstream: ws,
          source: "claude_code",
          payload: payload
        )

        render json: {}
      end

      def stop
        session = find_or_create_session
        ws = resolve_workstream

        session.run_events.create!(
          event_type: "session_completed",
          occurred_at: Time.current,
          workstream: ws,
          source: "claude_code",
          payload: {
            tool_calls_made: params[:tool_calls_made]
          }.compact
        )

        # Mark session completed and generate passport
        session.update!(status: "completed", completed_at: Time.current)

        if ws
          passport = PassportGenerator.new(session).generate!
          passport.update!(workstream: ws) unless passport.workstream_id
          passport.create_version!(trigger: "session_completed")
        end

        render json: {}
      end

      private

      def find_or_create_session
        session_id = params[:session_id] || "unknown-#{Time.now.to_i}"
        AgentSession.find_or_create_by!(external_session_id: session_id) do |s|
          s.provider = "claude_code"
          s.agent_name = "Claude Code"
          s.branch_name = current_branch
          s.status = "active"
          s.started_at = Time.current
          s.project = resolve_project
          s.workstream = resolve_workstream
        end
      end

      def resolve_workstream
        branch = current_branch
        return nil if branch.blank? || branch == "unknown"
        Workstream.find_or_create_for_branch(project: resolve_project, branch_name: branch)
      end

      def resolve_project
        @project ||= token_project
      end

      def current_branch
        # Try to detect from cwd if provided
        if params[:cwd].present?
          branch = `cd #{params[:cwd].shellescape} && git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
          return branch unless branch.empty?
        end
        params[:branch_name] || "unknown"
      end

      def project_name
        resolve_project.name
      end
    end
  end
end
