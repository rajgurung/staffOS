class DecisionLogsController < ApplicationController
  before_action :set_decision_log, only: [:show, :edit, :update, :destroy]

  def index
    @decision_logs = current_project.decision_logs.includes(:workstream).order(created_at: :desc)
    @decision_logs = @decision_logs.where(status: params[:status]) if params[:status].present?
  end

  def show
  end

  def new
    @decision_log = DecisionLog.new(status: "draft")
  end

  def create
    @decision_log = DecisionLog.new(decision_log_params)
    @decision_log.project = current_project
    if @decision_log.save
      redirect_to @decision_log, notice: "Decision log created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @decision_log.update(decision_log_params)
      redirect_to @decision_log, notice: "Decision log updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @decision_log.destroy
    redirect_to decision_logs_path, notice: "Decision log deleted."
  end

  private

  def set_decision_log
    @decision_log = DecisionLog.where(project: accessible_projects).find(params[:id])
  end

  def decision_log_params
    params.require(:decision_log).permit(:title, :context, :decision, :rationale, :consequences, :status, :run_passport_id)
  end
end
