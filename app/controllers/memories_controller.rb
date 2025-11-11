# For managing memories via the Settings page (all users).

class MemoriesController < ApplicationController
  before_action :set_memory, only: [ :edit, :update, :destroy ]

  def create
    @memory = current_user.memories.build(memory_params)
    @memory.author = current_user

    if @memory.save
      respond_to do |format|
        format.turbo_stream
        format.html do
          redirect_to edit_user_registration_path(active_tab: :memories), notice: "Memory added successfully."
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          flash.now[:error] = "Failed to add memory: #{@memory.errors.full_messages.to_sentence}"
          render :create, status: :unprocessable_entity
        end
        format.html do
          redirect_to edit_user_registration_path(active_tab: :memories), alert: "Failed to add memory: #{@memory.errors.full_messages.to_sentence}"
        end
      end
    end
  end

  def edit
    render :edit, formats: :turbo_stream
  end

  # Currently alowing all students to manage their memories.
  # If restrictions are needed, consider adding a teacher approval queue.
  def update
    if @memory.update(memory_params)
      render :update, formats: :turbo_stream
    else
      flash.now[:error] = "Failed to update memory: #{@memory.errors.full_messages.to_sentence}"
      render :edit, formats: :turbo_stream, status: :unprocessable_entity
    end
  end

  def destroy
    @memory.destroy!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@memory) }
      format.html do
        redirect_to edit_user_registration_path(active_tab: :memories), notice: "Memory deleted successfully."
      end
    end
  end

  private

  def set_memory
    @memory = current_user.memories.find(params[:id])
  end

  def memory_params
    params.expect(memory: [ :body ])
  end
end
