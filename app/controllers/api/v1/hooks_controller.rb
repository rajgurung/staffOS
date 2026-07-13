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

        # Privacy-enforcing CLIs (0.4.0+) strip source client-side and send the
        # derived counts instead; prefer those, fall back to deriving here for
        # older CLIs and opted-in full-capture projects.
        case tool
        when "Read"
          payload[:file] = input["file_path"]
          payload[:lines] = input["lines"]&.to_i || (output.to_s.lines.count if output)
        when "Edit", "Write"
          payload[:file] = input["file_path"]
          if input["additions"] || input["deletions"]
            payload[:additions] = input["additions"].to_i
            payload[:deletions] = input["deletions"].to_i
          elsif input["old_string"] && input["new_string"]
            payload[:additions] = input["new_string"].to_s.lines.count
            payload[:deletions] = input["old_string"].to_s.lines.count
          elsif tool == "Write" && input["content"]
            payload[:additions] = input["content"].to_s.lines.count
            payload[:deletions] = 0
          end
        when "Bash"
          payload[:command] = input["command"]
          payload[:exit_code] = input["exit_code"]&.to_i || (output.to_s.match?(/exit code/i) ? 1 : 0)
        end
        payload.compact!

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

        # The CLI sends what git says is actually on the branch (paths + line
        # counts vs the merge-base). Recorded before the passport rebuild so
        # the generator can score coverage against it. Only hash-shaped params
        # are accepted — anything else would break the stop flow mid-way.
        snapshot = params[:branch_snapshot]
        if ws && snapshot.is_a?(ActionController::Parameters)
          session.run_events.create!(
            event_type: "branch_snapshot",
            occurred_at: Time.current,
            workstream: ws,
            source: "claude_code",
            payload: snapshot.to_unsafe_h
          )
        end

        # Mark session completed, then rebuild the branch's living passport and
        # snapshot a version recording what this session changed.
        session.update!(status: "completed", completed_at: Time.current)

        if ws
          passport = PassportGenerator.new(ws).generate!
          passport.create_version!(trigger: "session_completed", agent_session: session)
        end

        render json: {}
      end

      private

      def find_or_create_session
        session_id = params[:session_id] || "unknown-#{Time.now.to_i}"
        # Scoped to the token's project: an external session id is only unique
        # per client, so a global lookup would let events from one project (or
        # another user's token) attach to an unrelated project's session.
        resolve_project.agent_sessions.find_or_create_by!(external_session_id: session_id) do |s|
          s.provider = "claude_code"
          s.agent_name = "Claude Code"
          s.branch_name = current_branch
          s.status = "active"
          s.started_at = Time.current
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
        # The branch is computed client-side (the server has no working tree) and
        # sent as branch_name. The old cwd git shell-out here could never work
        # remotely and was a command-injection surface.
        params[:branch_name].presence || "unknown"
      end

      def project_name
        resolve_project.name
      end
    end
  end
end
