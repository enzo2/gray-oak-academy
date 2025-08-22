# For generic LLM chats, not lessons.
class ConversationsController < ApplicationController
  before_action :set_conversation, only: [ :show, :update, :destroy ]
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

  def destroy
    @conversation.destroy
    set_conversations # Refresh the list of conversations
    redirect_to conversations_path
  end

  private

  def set_conversation
    conversation = Conversation.find(params[:id])
    # Ensure the conversation belongs to the current user, or one of his students if a teacher
    if conversation.user == current_user || current_user.students.include?(conversation.user)
      @conversation = conversation
    else
      redirect_to conversations_path, alert: "That conversation does not belong to you."
    end
  end

  def set_conversations
    @conversations = current_user.conversations.generic.order(created_at: :desc)
  end

  def get_task_system_prompt
    if current_user.role_teacher?
      Prompt.get_prompt(category: "teacher_assistant", user: current_user)
    else
      Prompt.get_prompt(category: "open_ended_student_chat", user: current_user)
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
