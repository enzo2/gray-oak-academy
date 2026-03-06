class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Authenticate entire app
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  # Allow unauthenticated access to PWA assets (manifest & service worker)
  skip_before_action :authenticate_user!, only: %i[manifest] # service_worker]
  # Exempt the service worker endpoint from CSRF protection
  # protect_from_forgery except: :service_worker

  def require_superuser
    unless current_user.role_superuser?
      flash[:alert] = "You are not authorized to access that."
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

  # Serve PWA manifest
  def manifest
    response.headers["Content-Type"] = "application/manifest+json; charset=utf-8"
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate" if Rails.env.development?
    render template: "pwa/manifest", formats: [ :json ], layout: false
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
      if llm_access_token_required?
        flash[:warning] = "This API has no shared token. Add your own API key or choose a shared provider in settings."
      else
        flash[:error] = "You need to configure an LLM first."
      end
      redirect_to edit_user_registration_path(active_tab: :api)
    end
  end

  def llm_access_token_required?
    settings = current_user.settings
    base_uri = settings.effective_llm_api_base_uri
    return false if base_uri.blank?
    return false if settings.llm_api_access_token.present?
    return false if settings.openai_oauth_usable_for_base_uri?(base_uri)

    shared_api = SupportedApi.selectable_for_teachers.exists?(api_base_uri: base_uri)
    env_base = ensure_trailing_slash(ENV["OPENAI_API_BASE_URL"])
    env_fallback = ENV["OPENAI_API_KEY"].present? && env_base.present? && env_base == base_uri
    !shared_api && !env_fallback
  end

  def ensure_trailing_slash(url)
    return url if url.blank? || url.end_with?("/")
    "#{url}/"
  end
end
