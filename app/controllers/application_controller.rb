class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Authenticate entire app
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  def require_superuser
    unless current_user.role_superuser?
      flash[:alert] = "You must be a superuser to access this page."
      redirect_to admin_root_path
    end
  end

  def require_admin
    unless current_user.role_admin? || current_user.role_superuser?
      flash[:alert] = "You must be an admin to access this page."
      redirect_to student_root_path
    end
  end

  # Root path for all users, redirects to appropriate dashboard
  def index
    if current_user.role_admin? || current_user.role_superuser?
      redirect_to admin_root_path
    elsif current_user.role_student?
      redirect_to student_root_path
    else
      redirect_to new_user_session_path
    end
  end

  # Provide a renderer with a signed-in user to be able to render template views outside controllers
  # eg.
  # renderer = ApplicationController.renderer_with_signed_in_user(user)
  # renderer.render template: 'notifications/show', layout: false, locals: { foo: 'bar' }
  def self.renderer_with_signed_in_user(user)
    Rails.logger.debug "Renderer with signed-in user requested: #{user.inspect}"
    ActionController::Renderer::RACK_KEY_TRANSLATION["warden"] ||= "warden"
    proxy = Warden::Proxy.new({}, Warden::Manager.new({})).tap { |i|
      i.set_user(user, scope: :user, store: false, run_callbacks: false)
    }
    renderer.new("warden" => proxy)
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :first_name, :last_name, :role, :signup_code ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :first_name, :last_name ])
  end

  def check_llm_configured
    return if current_user.settings.llm_configured?

    if current_user.role_student?
      flash.now[:warning] = "Your teacher must add an LLM before you can use the app."
    else
      flash.now[:warning] = "No default LLM configured. Please visit settings."
    end
  end

  def require_llm_configured
    return if current_user.settings.llm_configured?

    if current_user.role_student?
      flash[:error] = "Your teacher must add an LLM before you can chat."
      redirect_to student_root_path
    else
      flash[:error] = "You need to configure an LLM before you can do that."
      redirect_to edit_user_registration_path
    end
  end
end
