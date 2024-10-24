class MessagesController < ApplicationController
  # include ActionView::RecordIdentifier   ?why

  def create
    # Create a new Message from the message_params and add it to the conversation with the id from the params
    @message = Message.create(message_params.merge(conversation_id: params[:conversation_id], role: "user"))
    # Get completion and stream the response to the conversation view
    GetLlmCompletionJob.perform_later(conversation_id: @message.conversation_id)

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
