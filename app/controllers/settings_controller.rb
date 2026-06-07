class SettingsController < ApplicationController
  def index
    @user = current_user
    @projects = Project.all
    llm_tokens = RunPassport.sum(:input_tokens) + RunPassport.sum(:output_tokens)
    agent_tokens = AgentSession.all.sum { |s| s.metadata&.dig("tokens_used").to_i }
    @total_tokens = llm_tokens + agent_tokens
    @total_sessions = AgentSession.count
    @total_events = RunEvent.count
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
