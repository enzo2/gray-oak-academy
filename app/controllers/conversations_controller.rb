# For generic LLM chats, not lessons.
class ConversationsController < ApplicationController
  before_action :set_conversation, only: [ :show, :clear, :destroy ]
  def show
  end

  def index
    # Create a default conversation if none exist
    unless current_user.conversations.generic.any?
      Conversation.create!(user: current_user, title: "Chat 1", task_system_prompt: get_task_system_prompt)
    end

    # Load conversations not related to a lesson
    @conversations = current_user.conversations.generic.order(created_at: :desc)
    # Load the first conversation for display
    @conversation = @conversations.first
  end

  def create
    # Generate a title like "Chat 2" based on existing conversations count
    chat_number = current_user.conversations.count + 1
    title = "Chat #{chat_number}"

    @conversation = current_user.conversations.create(
      title: title,
      task_system_prompt: get_task_system_prompt
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

  def get_task_system_prompt
    if current_user.role_admin?
      Prompt.category_teacher_assistant.first.prompt
    else
      Prompt.category_open_ended_student_chat.first.prompt
    end
  end
end
