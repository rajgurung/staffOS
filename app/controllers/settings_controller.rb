class SettingsController < ApplicationController
  def index
    @user = current_user
    @projects = current_user.projects
    sessions = AgentSession.where(project_id: @projects.select(:id))
    passports = RunPassport.joins(:workstream).where(workstreams: { project_id: @projects.select(:id) })
    llm_tokens = passports.sum(:input_tokens) + passports.sum(:output_tokens)
    agent_tokens = sessions.sum { |s| s.metadata&.dig("tokens_used").to_i }
    @total_tokens = llm_tokens + agent_tokens
    @total_sessions = sessions.count
    @total_events = RunEvent.joins(:agent_session).where(agent_sessions: { project_id: @projects.select(:id) }).count
  end

  def update_profile
    if current_user.update(profile_params)
      redirect_to settings_path, notice: "Profile updated."
    else
      redirect_to settings_path, alert: "Failed to update profile."
    end
  end

  private

  def profile_params
    params.require(:user).permit(:name, :email)
  end
end
