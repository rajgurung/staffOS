class WorkstreamsController < ApplicationController
  before_action :set_workstream, only: [:show, :edit, :update, :promote]

  def index
    @workstreams = current_project ? current_project.workstreams.recent.includes(:run_passport, :project) : Workstream.none
    @workstreams = @workstreams.where(status: params[:status]) if params[:status].present?
  end

  def show
    @sessions = @workstream.agent_sessions.order(started_at: :desc)
    @passport = @workstream.run_passport
    @events = @workstream.run_events.order(occurred_at: :desc).limit(20)
    @documents = @workstream.documents
    @decisions = @workstream.decision_logs
    @files = @workstream.all_files_touched
  end

  def edit
  end

  def update
    if @workstream.update(workstream_params)
      redirect_to @workstream, notice: "Workstream updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def promote
    @workstream.promote_to_project!
    redirect_to workstreams_path, notice: "#{@workstream.display_name} merged. Documents promoted to project level."
  end

  private

  def set_workstream
    @workstream = Workstream.where(project: accessible_projects).find(params[:id])
  end

  def workstream_params
    params.require(:workstream).permit(:title, :status, :description)
  end
end
