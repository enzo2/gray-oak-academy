module Admin
  class BaseController < ApplicationController
    # Admin controllers should inherit from this one, Admin::BaseController.

    # Ensure all admin controllers require admin login.
    before_action :require_admin

    # All admin controller views will be inserted into layouts/admin/base.html.erb.
  end
end
