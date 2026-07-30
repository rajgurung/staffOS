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

  # Set or remove the user's own Anthropic key. The key is write-only from the
  # UI: it is never rendered back, only a masked hint.
  def update_api_key
    if params[:remove].present?
      current_user.update!(anthropic_api_key: nil)
      redirect_to settings_path, notice: "Anthropic API key removed. AI reviewers fall back to heuristics."
    elsif current_user.update(anthropic_api_key: params.dig(:user, :anthropic_api_key).to_s.strip)
      redirect_to settings_path, notice: "Anthropic API key saved. AI Council and Smart Summary now use your key."
    else
      redirect_to settings_path, alert: current_user.errors.full_messages.to_sentence
    end
  end

  private

  def profile_params
    params.require(:user).permit(:name, :email)
  end
end
