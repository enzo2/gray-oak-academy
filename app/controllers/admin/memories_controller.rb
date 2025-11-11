include ActionView::RecordIdentifier

module Admin
  class MemoriesController < Admin::BaseController
    before_action :set_student
    before_action :set_memory, only: [ :edit, :update, :destroy, :toggle_hidden ]

    def create
      @memory = @student.memories.build(memory_params)
      @memory.author ||= current_user

      if @memory.save
        respond_to do |format|
          format.turbo_stream # app/views/admin/memories/create.turbo_stream.erb
          format.html { redirect_to admin_student_path(@student, active_tab: :memories), notice: "Memory added successfully." }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            flash.now[:error] = "Failed to add memory: #{@memory.errors.full_messages.to_sentence}"
            render :create, status: :unprocessable_entity
          end
          format.html do
            redirect_to admin_student_path(@student, active_tab: :memories),
                        alert: "Failed to add memory: #{@memory.errors.full_messages.to_sentence}"
          end
        end
      end
    end

    def edit
      # Form rendered inline via Turbo Stream
    end

    def update
      if @memory.update(memory_params)
        respond_to do |format|
          format.turbo_stream # app/views/admin/memories/update.turbo_stream.erb
          format.html { redirect_to admin_student_path(@student, active_tab: :memories), notice: "Memory updated successfully." }
        end
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @memory.destroy!

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@memory)) }
        format.html { redirect_to admin_student_path(@student, active_tab: :memories), notice: "Memory deleted successfully." }
      end
    end

    def toggle_hidden
      @memory.update!(hidden_from_student: !@memory.hidden_from_student?)
      render turbo_stream: turbo_stream.replace(@memory)
    end

    private

    def set_student
      @student = User.find(params[:student_id])
    end

    def set_memory
      @memory = @student.memories.find(params[:id])
    end

    def memory_params
      params.require(:memory).permit(:body, :hidden_from_student)
    end
  end
end
