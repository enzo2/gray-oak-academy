# For generic LLM chats, not lessons.
class ConversationsController < ApplicationController
  include LlmCompletionRouting
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
    maybe_seed_applet_revision_chat(@conversation)
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
    conversation = authorized_conversation_scope.find_by(id: params[:id])
    if conversation
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

  def maybe_seed_applet_revision_chat(conversation)
    return unless current_user.role_teacher?
    return unless params[:starter_template].to_s == "applet_revision"

    applet = applet_scope_for_teacher.find_by(id: params[:applet_id].to_i)
    unless applet
      flash[:warning] = "Couldn't load the selected applet for revision. The chat was created without starter context."
      return
    end

    context_resource = resolve_context_resource(applet)
    return if context_resource == :invalid

    context_lesson = resolve_context_lesson
    return if context_lesson == :invalid

    # Seed an explicit first user turn so the assistant has durable, tool-usable context.
    conversation.messages.create!(
      role: "user",
      content: applet_revision_starter_prompt(applet: applet, resource: context_resource, lesson: context_lesson)
    )
    enqueue_llm_completion(conversation: conversation)
  rescue StandardError => e
    Rails.logger.error("Failed to seed applet revision starter chat: #{e.message}")
    flash[:warning] = "The chat was created, but the starter context could not be prepared."
  end

  def applet_scope_for_teacher
    Applet.where(user_id: current_user.id)
          .or(Applet.where(user_id: current_user.students.select(:id)))
  end

  def resolve_context_resource(applet)
    explicit_id = params[:resource_id].presence
    return applet.resource unless explicit_id

    resource = Resource.where(teacher_id: [ current_user.id, nil ]).find_by(id: explicit_id.to_i)
    unless resource
      flash[:warning] = "Couldn't load the selected resource for starter context. The chat was created without starter context."
      return :invalid
    end

    if applet.resource_id.present? && applet.resource_id != resource.id
      flash[:warning] = "The selected resource does not match this applet. The chat was created without starter context."
      return :invalid
    end

    resource
  end

  def resolve_context_lesson
    lesson_id = params[:lesson_id].presence
    return nil unless lesson_id

    lesson = Lesson.joins(:course).where(courses: { teacher_id: current_user.id }).find_by(id: lesson_id.to_i)
    return lesson if lesson

    flash[:warning] = "Couldn't load the selected lesson for starter context. The chat was created without starter context."
    :invalid
  end

  def applet_revision_starter_prompt(applet:, resource:, lesson:)
    context = {
      applet_id: applet.id,
      applet_title: applet.title,
      resource_id: resource&.id,
      resource_description: resource&.description,
      lesson_id: lesson&.id,
      lesson_title: lesson&.title
    }.compact

    <<~PROMPT
      I want to revise an existing applet for this curriculum.

      Context:
      #{JSON.pretty_generate(context)}

      Please help me revise this applet. First, retrieve the current code using Manage_Applets with action "get" and this applet_id. Then ask concise clarifying questions if needed, propose improvements, and use Manage_Applets with action "upsert" and this applet_id once I confirm changes. If I ask to attach it to lesson resources, use Manage_Applets action "save_as_resource" with the appropriate lesson_id.
    PROMPT
  end
end
