require "test_helper"

class GenerateImageJobTest < ActiveJob::TestCase
  def setup
    @conversation = conversations(:student_generic_conversation)
    @user = @conversation.user
  end

  test "creates tool message with image" do
    temp_image = Tempfile.new([ "test", ".jpg" ])
    temp_image.write("fake image content")
    temp_image.rewind

    ImageGenerationService.stub :generate, temp_image do
      GenerateImageJob.perform_now(
        conversation_id: @conversation.id,
        user_id: @user.id,
        prompt: "draw a cat",
        tool_call_id: "tc-job-1"
      )
    end

    msg = @conversation.messages.role_tool.last
    assert_not_nil msg
    assert_equal "tc-job-1", msg.tool_call_id
    assert_equal GenerateImageJob::SUCCESS_MESSAGE, msg.content
    assert_equal 1, msg.images.count
    temp_image.close
    temp_image.unlink
  end

  test "creates failure tool message when generation raises" do
    ImageGenerationService.stub :generate, ->(**_args) { raise OpenAiError, "boom" } do
      GenerateImageJob.perform_now(
        conversation_id: @conversation.id,
        user_id: @user.id,
        prompt: "draw a cat",
        tool_call_id: "tc-job-2"
      )
    end

    msg = @conversation.messages.role_tool.last
    assert_not_nil msg
    assert_equal "tc-job-2", msg.tool_call_id
    assert_match(/Image generation failed: boom/, msg.content)
  end
end
