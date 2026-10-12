module Api
  module V1
    # Read-only view of a branch's living passport for `staffos passport`.
    # Always requires a token, even in development: reads must never fall
    # back to the name-based project lookup the ingest endpoints allow.
    class PassportsController < Api::BaseController
      def show
        return render json: { error: "Unauthorized" }, status: :unauthorized unless current_api_token

        workstream = current_api_token.project.workstreams.find_by(branch_name: params[:branch].to_s)
        passport = workstream&.run_passport
        unless passport
          return render json: { error: "No passport for this branch yet" }, status: :not_found
        end

        render json: {
          project: workstream.project.name,
          branch: workstream.branch_name,
          readiness_score: passport.readiness_score,
          risk_level: passport.risk_level,
          human_review_required: passport.human_review_required,
          sessions_count: passport.sessions_count,
          files_count: passport.files_count,
          test_status: passport.test_status,
          missing_checks: Array(passport.missing_checks).map { |c| c.slice("check", "severity") },
          recommended_actions: Array(passport.recommended_actions).map { |a| a.slice("action", "priority") },
          updated_at: passport.updated_at.iso8601,
          url: run_passport_url(passport)
        }
      end
    end
  end
end
