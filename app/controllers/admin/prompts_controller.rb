module Admin
  class PromptsController < Admin::BaseController
    # set_prompt contains authorization logic
    before_action :set_prompt, only: [ :edit, :update, :destroy ]

    def index
      @user_prompts = Prompt.where(teacher: current_user).order(:category)
      @default_prompts = Prompt.where(teacher: nil).order(:category)
    end

    # def show
    # end

    def new
      @prompt = Prompt.new
    end

    # All default prompts are in the db seeds, so any newly created prompts here
    # will belong to a specific teacher and serve as overrides.
    def create
      @prompt = Prompt.new(prompt_params)
      @prompt.teacher = current_user

      if @prompt.save
        redirect_to admin_prompts_path
      else
        respond_to do |format|
          format.turbo_stream { render :create, status: :unprocessable_content }
        end
      end
    end

    def edit
    end

    def update
      if @prompt.update(prompt_params)
        redirect_to admin_prompts_path
      else
        respond_to do |format|
          format.turbo_stream { render :update, status: :unprocessable_content }
        end
      end
    end

    def destroy
      @prompt.destroy
      respond_to do |format|
        format.turbo_stream
      end
    end

    private

    def set_prompt
      @prompt = Prompt.find(params[:id])
      # Superusers can access any prompt. Admins can only update/destroy their own prompts.
      unless current_user.role_superuser? || @prompt.teacher == current_user
        flash[:warning] = "You are not authorized to edit this prompt."
        redirect_to admin_prompts_path
      end
      # Protect system prompts from deletion
      if @prompt.teacher.nil? && params[:action] == "destroy"
        flash[:warning] = "You cannot delete the default prompts."
        redirect_to admin_prompts_path
      end
    end

    def prompt_params
      params.require(:prompt).permit(:title, :category, :prompt)
    end
  end
end
