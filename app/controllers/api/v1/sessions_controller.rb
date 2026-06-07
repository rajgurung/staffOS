module Api
  module V1
    class SessionsController < Api::BaseController
      def complete
        session = AgentSession.find_by!(external_session_id: params[:session_id])
        session.update!(status: "completed", completed_at: Time.current)

        passport = PassportGenerator.new(session).generate!

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
