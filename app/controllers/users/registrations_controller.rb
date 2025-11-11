# frozen_string_literal: true

# Overrides for Devise::RegistrationsController
class Users::RegistrationsController < Devise::RegistrationsController
  # before_action :configure_sign_up_params, only: [:create]
  # before_action :configure_account_update_params, only: [:update]
  before_action :check_signup_mode, only: [ :new, :create ]
  before_action :set_memories, only: [ :edit, :update ]

  # GET /resource/sign_up
  # def new
  #  super
  # end

  # POST /resource
  # def create
  #  super
  # end

  # GET /resource/edit
  def edit
    # This view is used as the user settings page-- also includes tabs besides Devise-controlled user settings.
    # Allow tab to be specified via params.
    @active_tab = params[:active_tab].presence&.to_sym || :api
    super
  end

  # PUT /resource
  def update
    @active_tab = :account
    super
  end

  # DELETE /resource
  # def destroy
  #   super
  # end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  # def cancel
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_up_params
  #   devise_parameter_sanitizer.permit(:sign_up, keys: [:attribute])
  # end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_account_update_params
  #   devise_parameter_sanitizer.permit(:account_update, keys: [:attribute])
  # end

  # The path used after sign up.
  # def after_sign_up_path_for(resource)
  #   super(resource)
  # end

  # The path used after sign up for inactive accounts.
  # def after_inactive_sign_up_path_for(resource)
  #   super(resource)
  # end
  #
  private

  def check_signup_mode
    if ENV["ALLOW_SIGNUPS"] != "true"
      Rails.logger.info "Signup attempted, but signups are currently disabled."
      flash[:alert] = "Signups are currently not allowed."
      redirect_to root_path, status: :see_other
    end
  end

  # Needed for the memories tab on the user settings page.
  # Would be better to move this to MemoriesController and import here?
  def set_memories
    # Ensure students only see non-hidden memories.
    @memories = if current_user.role_student?
      current_user.memories.visible_to_students.order(created_at: :desc)
    else
      current_user.memories.order(created_at: :desc)
    end
  end
end
