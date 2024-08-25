class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Authenticate entire app
  before_action :authenticate_user!

  def require_admin
    unless current_user.role_admin?
      flash[:alert] = "You must be an admin to access this page."
      redirect_to students_root_path
    end
  end


  def index
    if current_user.role_admin?
      redirect_to admin_root_path
    elsif current_user.role_student?
      redirect_to students_root_path
    else
      redirect_to new_user_session_path
    end
  end
end
