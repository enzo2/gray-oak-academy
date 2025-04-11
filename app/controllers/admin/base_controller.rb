module Admin
  class BaseController < ApplicationController
    # Ensure all admin controllers require admin login.
    # Other admin controllers should inherit from this one.
    before_action :require_admin
  end
end
