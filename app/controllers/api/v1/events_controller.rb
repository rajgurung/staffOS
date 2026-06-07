module Api
  module V1
    class EventsController < Api::BaseController
      def create
        session = find_or_create_session
        workstream = resolve_workstream(session)

        event = session.run_events.create!(
          event_type: params[:event_type],
          occurred_at: params[:occurred_at] || Time.current,
          payload: params[:payload] || {},
          source: params[:source] || "claude_code",
          workstream: workstream
        )

        render json: { id: event.id, workstream_id: workstream&.id, status: "captured" }, status: :created
      end

      private

      def find_or_create_session
        AgentSession.find_or_create_by!(
          external_session_id: params[:session_id]
        ) do |s|
          s.provider = params[:provider] || "claude_code"
          s.agent_name = params[:agent_name] || "Claude Code"
          s.branch_name = params[:branch_name]
          s.status = "active"
          s.started_at = Time.current
          s.project = Project.first_or_create!(
            name: params[:project_name] || "Default",
            repo_name: params[:repo_name] || "unknown"
          )
        end
      end

      def resolve_workstream(session)
        branch = params[:branch_name] || session.branch_name
        return nil if branch.blank?

        ws = Workstream.find_or_create_for_branch(
          project: session.project,
          branch_name: branch
        )
        session.update!(workstream: ws) unless session.workstream_id == ws.id
        ws
      end
    end
  end
end
