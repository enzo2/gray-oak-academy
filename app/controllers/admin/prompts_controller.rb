module Admin
  class PromptsController < ApplicationController
    before_action :require_admin
    before_action :set_prompt, only: [ :edit, :update, :destroy ]

    def index
      @prompts = Prompt.order(:category)
    end

    # def show
    # end

    def new
      @prompt = Prompt.new
    end

    def create
      @prompt = Prompt.new(prompt_params)
      @prompt.teacher = current_user

      if @prompt.save
        redirect_to admin_prompts_path
      else
        respond_to do |format|
          format.turbo_stream { render :create, status: :unprocessable_entity }
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
          format.turbo_stream { render :update, status: :unprocessable_entity }
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
    end

    def prompt_params
      params.require(:prompt).permit(:title, :category, :prompt)
    end
  end
end
