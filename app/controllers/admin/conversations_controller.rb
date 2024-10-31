module Admin
  class ConversationsController < ApplicationController
    before_action :require_admin

    def index
      unless current_user.conversations.generic.any?
        Conversation.create!(user: current_user, title: "Chat 1", task_system_prompt: Prompt.category_teacher_assistant.first.prompt)
      end

      # Load conversations not related to a lesson
      @conversations = current_user.conversations.generic.order(created_at: :desc)
      # Load the first conversation for display
      @conversation = @conversations.first
    end

    # Remainder of logic in the non-namespaced ConversationsController for both teachers and students
  end
end
