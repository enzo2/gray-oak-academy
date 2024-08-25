class AdminController < ApplicationController
  before_action :require_admin

  def dashboard
    render "dashboard"
  end
end
