require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  test "teacher can create applet revision starter chat with auto-sent context" do
    teacher = users(:admin)
    sign_in(teacher)

    applet = Applet.create!(title: "Revision Target", code: "console.log('hello');", user: teacher)
    resource = Resource.create!(teacher: teacher, category: "Applet", description: "Applet resource", applet: applet)
    lesson = lessons(:one)

    with_prompt_stubs do
      assert_enqueued_jobs 1, only: GetLlmCompletionJob do
        post conversations_path, params: {
          starter_template: "applet_revision",
          applet_id: applet.id,
          resource_id: resource.id,
          lesson_id: lesson.id
        }
      end
    end

    conversation = Conversation.order(:created_at).last
    assert_redirected_to conversation_path(conversation)
    assert_equal teacher.id, conversation.user_id
    assert_equal 1, conversation.messages.count

    starter = conversation.messages.last
    assert_equal "user", starter.role
    assert_includes starter.content, "\"applet_id\": #{applet.id}"
    assert_includes starter.content, "\"resource_id\": #{resource.id}"
    assert_includes starter.content, "\"lesson_id\": #{lesson.id}"
    refute_includes starter.content, applet.code
    assert_includes starter.content, "Manage_Applets with action \"get\""
  end

  test "teacher applet revision starter chat enqueues responses job for openrouter" do
    teacher = users(:admin)
    teacher.setting.update!(llm_api_base_uri: "https://openrouter.ai/api/v1/")
    sign_in(teacher)

    applet = Applet.create!(title: "Revision Target", code: "console.log('hello');", user: teacher)
    resource = Resource.create!(teacher: teacher, category: "Applet", description: "Applet resource", applet: applet)
    lesson = lessons(:one)

    with_prompt_stubs do
      assert_enqueued_jobs 1, only: GetResponsesCompletionJob do
        assert_enqueued_jobs 0, only: GetLlmCompletionJob do
          post conversations_path, params: {
            starter_template: "applet_revision",
            applet_id: applet.id,
            resource_id: resource.id,
            lesson_id: lesson.id
          }
        end
      end
    end
  end

  test "invalid applet revision context falls back to plain new chat with warning" do
    teacher = users(:admin)
    other_teacher = users(:admin2)
    sign_in(teacher)

    unauthorized_applet = Applet.create!(title: "Other Teacher Applet", code: "console.log('nope');", user: other_teacher)

    with_prompt_stubs do
      assert_enqueued_jobs 0, only: GetLlmCompletionJob do
        post conversations_path, params: {
          starter_template: "applet_revision",
          applet_id: unauthorized_applet.id
        }
      end
    end

    conversation = Conversation.order(:created_at).last
    assert_redirected_to conversation_path(conversation)
    assert_equal teacher.id, conversation.user_id
    assert_equal 0, conversation.messages.count
    assert_includes flash[:warning], "without starter context"
  end

  private

  def with_prompt_stubs
    Prompt.stub(:get_prompt, "Stub prompt") { yield }
  end
end
