class ConversationsController < ApplicationController
  before_action :set_conversation, only: [ :show, :clear ]

  def show
  end

  def create
    if current_user.role_admin?
      task_system_prompt = Prompt.category_teacher_assistant.first.prompt
    elsif current_user.role_student?
      task_system_prompt = Prompt.category_open_ended_student_chat.first.prompt
    end

    @conversation = Conversation.create(conversation_params, user: current_user, task_system_prompt: task_system_prompt)
  end

  def clear
    # For generic conversations - make sure the conversation is not associated with a lesson in progress first
    # (Otherwise, for lessons would be correct to maintain the conversation record unless the lesson is restarted)
    if @conversation.lesson_progress.nil?
      @conversation.messages.destroy_all
      respond_to do |format|
        format.turbo_stream
      end
    end
  end

  private

  def set_conversation
    @conversation = Conversation.find(params[:id])
  end

  def conversation_params
    params.require(:conversation).permit(:title)
  end
end
