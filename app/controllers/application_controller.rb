class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  before_action :authenticate_user!
end
