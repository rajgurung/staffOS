class ConnectController < ApplicationController
  def index
    @project = current_project
    return unless @project

    @token = @project.api_tokens.first || @project.api_tokens.create!(name: "Auto-generated")
  end
end
