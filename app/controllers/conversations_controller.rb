# For generic LLM chats, not lessons.
class ConversationsController < ApplicationController
  before_action :set_conversation, only: [ :show, :clear, :destroy ]
  def show
  end

  def create
    if current_user.role_admin?
      task_system_prompt = Prompt.category_teacher_assistant.first.prompt
    elsif current_user.role_student?
      task_system_prompt = Prompt.category_open_ended_student_chat.first.prompt
    end

    # Generate a title like "Chat 2" based on existing conversations count
    chat_number = current_user.conversations.count + 1
    title = "Chat #{chat_number}"

    @conversation = current_user.conversations.create(
      title: title,
      task_system_prompt: task_system_prompt
    )
    set_conversations
    respond_to do |format|
      format.turbo_stream
    end
  end

  def destroy
    @conversation.destroy
    set_conversations
    respond_to do |format|
      format.turbo_stream
    end
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

  def set_conversations
    @conversations = current_user.conversations.generic.order(created_at: :desc)
  end
end
