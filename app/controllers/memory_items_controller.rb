class MemoryItemsController < ApplicationController
  before_action :set_memory_item, only: [:show, :edit, :update, :destroy]

  def index
    @memory_items = MemoryItem.includes(:project).active.order(created_at: :desc)
    @memory_items = @memory_items.by_type(params[:type]) if params[:type].present?
  end

  def show
  end

  def new
    @memory_item = MemoryItem.new(memory_type: params[:type] || "decision")
  end

  def create
    @memory_item = MemoryItem.new(memory_item_params)
    @memory_item.project = Project.first
    if @memory_item.save
      redirect_to @memory_item, notice: "Memory item created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @memory_item.update(memory_item_params)
      redirect_to @memory_item, notice: "Memory item updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @memory_item.destroy
    redirect_to memory_items_path, notice: "Memory item deleted."
  end

  private

  def set_memory_item
    @memory_item = MemoryItem.find(params[:id])
  end

  def memory_item_params
    params.require(:memory_item).permit(:memory_type, :content, :confidence, :expires_at, :document_id)
  end
end
