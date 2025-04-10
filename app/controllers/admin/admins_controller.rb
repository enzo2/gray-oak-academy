module Admin
  class AdminsController < ApplicationController
    before_action :require_admin

    def dashboard
    end
  end
end
