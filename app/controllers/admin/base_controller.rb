module Admin
  class BaseController < ApplicationController
    # Admin controllers should inherit from this one, Admin::BaseController.
    # Then, all admin controller views will be inserted into layouts/admin/base.html.erb.

    # Ensure all admin controllers require admin login.
    before_action :require_admin
  end
end
