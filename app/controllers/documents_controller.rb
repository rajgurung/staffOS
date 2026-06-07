class DocumentsController < ApplicationController
  before_action :set_document, only: [:show, :edit, :update, :destroy]

  def index
    @documents = Document.includes(:project, :run_passport).order(created_at: :desc)
    @documents = @documents.where(document_type: params[:type]) if params[:type].present?
  end

  def show
  end

  def new
    @document = Document.new(document_type: params[:type] || "adr")
  end

  def create
    @document = Document.new(document_params)
    @document.project = Project.first
    if @document.save
      redirect_to @document, notice: "Document created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @document.update(document_params)
      redirect_to @document, notice: "Document updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy
    redirect_to documents_path, notice: "Document deleted."
  end

  private

  def set_document
    @document = Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:title, :document_type, :content_markdown, :status, :run_passport_id)
  end
end
