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
    @conversation = current_user.conversations.create(
      title: generate_unique_chat_title,
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

  def generate_unique_chat_title
    base_title = "Chat"
    counter = 1
    loop do
      title = "#{base_title} #{counter}"
      break title unless current_user.conversations.exists?(title: title)
      counter += 1
    end
  end
end
