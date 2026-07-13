module Api
  module V1
    class SessionsController < Api::BaseController
      def complete
        session = token_project.agent_sessions.find_by!(external_session_id: params[:session_id])
        session.update!(status: "completed", completed_at: Time.current)

        unless session.workstream
          return render json: { error: "session has no workstream (unknown branch); no passport generated" },
            status: :unprocessable_entity
        end

        passport = PassportGenerator.new(session.workstream).generate!
        passport.create_version!(trigger: "session_completed", agent_session: session)

        render json: {
          passport_id: passport.id,
          risk_level: passport.risk_level,
          readiness_score: passport.readiness_score,
          human_review_required: passport.human_review_required
        }, status: :ok
      end
    end
  end
end
