class AdminController < ApplicationController
  before_action :require_admin

  def dashboard
  end
end
