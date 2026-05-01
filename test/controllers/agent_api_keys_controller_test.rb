require "test_helper"

class AgentApiKeysControllerTest < ActionDispatch::IntegrationTest
  test "teacher can create key and sees token once" do
    sign_in users(:admin)

    assert_difference("AgentApiKey.count", 1) do
      post agent_api_keys_path, params: { agent_api_key: { name: "OpenClaw" } }
    end

    assert_redirected_to edit_user_registration_path(active_tab: :agent_access)
    assert flash[:agent_api_token].to_s.start_with?("goa_live_")
  end

  test "student cannot create key" do
    sign_in users(:student)

    assert_no_difference("AgentApiKey.count") do
      post agent_api_keys_path, params: { agent_api_key: { name: "Nope" } }
    end

    assert_redirected_to student_root_path
  end

  test "teacher can revoke own key" do
    teacher = users(:admin)
    key, = AgentApiKey.create_with_token!(user: teacher, name: "Hermes")
    sign_in teacher

    delete agent_api_key_path(key)

    assert_redirected_to edit_user_registration_path(active_tab: :agent_access)
    assert key.reload.revoked?
  end

  test "teacher can download generated skill markdown" do
    sign_in users(:admin)

    get user_settings_agent_skill_path

    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_includes response.body, "# Gray Oak Academy Teacher Agent Skill"
    assert_includes response.body, "Teaching principles"
    assert_includes response.body, "Be friendly and encouraging"
    assert_includes response.body, "External agents must not answer those teacher questions"
  end

  test "agent access settings renders recent activity drawer" do
    teacher = users(:admin)
    key, = AgentApiKey.create_with_token!(user: teacher, name: "Hermes")
    AgentApiEvent.create!(
      user: teacher,
      agent_api_key: key,
      request_method: "POST",
      path: "/api/agent/v1/command",
      command: "get_course",
      status: 200,
      record_ids: { courses: [ courses(:one).id ] },
      requested_at: Time.current
    )
    sign_in teacher

    get edit_user_registration_path(active_tab: :agent_access)

    assert_response :success
    assert_includes response.body, "Recent Activity"
    assert_includes response.body, "<details class=\"group border-t border-stone-200 pt-4 dark:border-stone-700\" open>"
    assert_includes response.body, "Latest 1"
    assert_includes response.body, "get_course"
  end

  test "agent access settings escapes generated skill preview" do
    teacher = users(:admin)
    Prompt.create!(
      title: "Unsafe Teaching Principles",
      category: "teaching_principles",
      prompt: "<script>alert('x')</script><b>Prefer Socratic prompts.</b>",
      teacher: teacher
    )
    sign_in teacher

    get edit_user_registration_path(active_tab: :agent_access)

    assert_response :success
    assert_includes response.body, "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"
    assert_includes response.body, "&lt;b&gt;Prefer Socratic prompts.&lt;/b&gt;"
    assert_not_includes response.body, "<script>alert('x')</script>"
  end
end
