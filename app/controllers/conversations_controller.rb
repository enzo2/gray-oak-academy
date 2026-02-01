# For generic LLM chats, not lessons.
class ConversationsController < ApplicationController
  before_action :set_conversation, only: [ :show, :update, :destroy, :clear ]
  before_action :require_llm_configured, only: [ :index, :show ]

  def index
    # Redirect to the most recent generic conversation
    conversation = current_user.conversations.generic.order(created_at: :desc).first
    if conversation
      redirect_to conversation_path(conversation)
    else
      # If no conversation exists, create one and redirect
      conversation = Conversation.create!(user: current_user, title: "Chat 1", task_system_prompt: get_task_system_prompt)
      redirect_to conversation_path(conversation)
    end
  end

  def show
    set_conversations
    AutoNameConversationJob.perform_later(conversation: @conversation) if @conversation.auto_name_candidate?
  end

  def create
    @conversation = current_user.conversations.create(
      title: generate_unique_chat_title,
      task_system_prompt: get_task_system_prompt
    )
    redirect_to conversation_path(@conversation) # Show the new conversation.
  end


  def update
    # Only the title can be updated.
    if @conversation.update(conversation_params)
      redirect_to conversation_path(@conversation), notice: "Conversation updated."
    else
      redirect_to conversation_path(@conversation), status: :unprocessable_content, alert: "Failed to update conversation."
    end
  end

  def clear
    # For generic conversations - make sure the conversation is not associated with a lesson in progress first
    # (For lessons would be correct to maintain the conversation record unless the lesson is restarted)
    if @conversation.lesson_progress.nil?
      @conversation.messages.destroy_all
      redirect_to conversation_path(@conversation), status: :see_other, success: "Conversation cleared."
    else
      redirect_to conversation_path(@conversation), status: :unprocessable_content, alert: "Cannot clear a conversation associated with a lesson in progress."
    end
  end

  def destroy
    @conversation.destroy
    set_conversations # Refresh the list of conversations
    redirect_to conversations_path, status: :see_other
  end

  private

  def set_conversation
    conversation = Conversation.find(params[:id])
    # Ensure the conversation belongs to the current user, or one of his students if a teacher
    if conversation.user == current_user || current_user.students.include?(conversation.user) || current_user.role_superuser?
      @conversation = conversation
    else
      redirect_to conversations_path, status: :forbidden, alert: "That conversation does not belong to you."
    end
  end

  def set_conversations
    @conversations = current_user.conversations.generic.order(created_at: :desc)
  end

  def get_task_system_prompt
    generative_guidelines = Prompt.get_prompt(category: "generative_guidelines", user: current_user)
    if current_user.role_teacher?
      generative_guidelines + "\n\n" + Prompt.get_prompt(category: "teacher_assistant", user: current_user)
    else
      generative_guidelines + "\n\n" + Prompt.get_prompt(category: "open_ended_student_chat", user: current_user)
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

  def conversation_params
    params.require(:conversation).permit(:title)
  end
end
