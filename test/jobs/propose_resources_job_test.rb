require "test_helper"

class ProposeResourcesJobTest < ActiveSupport::TestCase
  test "propose resources updates suggested_resources from responses output" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    app_setting = AppSetting.settings
    app_setting.update!(openai_agent_model: "gpt-5.2", openai_agent_supported_api_id: supported_apis(:openai).id)

    complete_calls = []
    wait_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      complete_calls << { messages: messages, kwargs: kwargs }
      { "id" => "resp_1", "status" => "queued", "output" => [] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **kwargs|
      wait_calls << { response_id: response_id, kwargs: kwargs }
      {
        "id" => "resp_1",
        "status" => "completed",
        "output" => [
          {
            "type" => "message",
            "content" => [
              {
                "type" => "output_text",
                "text" => "{\"suggested_resources\":[{\"type\":\"Video\",\"description\":\"NASA refraction demonstration video\"}]}"
              }
            ]
          }
        ]
      }
    end
    fake_client.define_singleton_method(:output_text) do |_response_hash|
      "{\"suggested_resources\":[{\"type\":\"Video\",\"description\":\"NASA refraction demonstration video\"}]}"
    end

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    captured_new_kwargs = nil

    OpenaiResponsesService.stub(:new, ->(**kwargs) { captured_new_kwargs = kwargs; fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          ProposeResourcesJob.perform_now(lesson_plan, teacher, source: "teacher_chat_tool")
        end
      end
    end

    lesson_plan.reload
    assert_equal "completed", lesson_plan.generation_stage
    assert_equal "NASA refraction demonstration video", lesson_plan.suggested_resources.first["Video"]
    assert_equal teacher, captured_new_kwargs[:current_user]
    assert_equal true, captured_new_kwargs[:agent_run]
    assert_nil captured_new_kwargs[:base_uri]
    assert_nil captured_new_kwargs[:access_token]
    assert_nil captured_new_kwargs[:model]
    assert_equal "propose_resources", complete_calls.first.dig(:kwargs, :metadata, :run_type)
    assert_equal true, complete_calls.first.dig(:kwargs, :background)
    assert_equal teacher.id.to_s, complete_calls.first.dig(:kwargs, :metadata, :teacher_id)
    assert_equal lesson_plan.id.to_s, complete_calls.first.dig(:kwargs, :metadata, :lesson_plan_id)
    assert_equal "teacher_chat_tool", complete_calls.first.dig(:kwargs, :metadata, :source)
    assert_nil complete_calls.first.dig(:kwargs, :metadata, :task_preview)
    assert_nil complete_calls.first.dig(:kwargs, :metadata, :task_full)
    assert_equal "resp_1", wait_calls.first[:response_id]
  end

  test "propose resources automatically reverts published lesson plan to draft" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    lesson_plan.update!(content: [ { "Intro" => "Ready" } ], status: "published")
    app_setting = AppSetting.settings
    app_setting.update!(openai_agent_model: "gpt-5.2")

    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |_messages = nil, **_kwargs|
      { "id" => "resp_1", "status" => "queued", "output" => [] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |_response_id, **_kwargs|
      {
        "id" => "resp_1",
        "status" => "completed",
        "output" => [
          {
            "type" => "message",
            "content" => [
              { "type" => "output_text", "text" => "{\"suggested_resources\":[]}" }
            ]
          }
        ]
      }
    end
    fake_client.define_singleton_method(:output_text) { |_response_hash| "{\"suggested_resources\":[]}" }

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          ProposeResourcesJob.perform_now(lesson_plan, teacher, source: "teacher_chat_tool")
        end
      end
    end

    assert_equal "draft", lesson_plan.reload.status
  end

  test "propose resources requests a retry turn after any tool execution error" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    app_setting = AppSetting.settings
    app_setting.update!(openai_agent_model: "gpt-5.2", openai_agent_supported_api_id: supported_apis(:openai).id)

    complete_calls = []
    wait_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      complete_calls << { messages: messages, kwargs: kwargs }
      response_id = "resp_#{complete_calls.size}"
      { "id" => response_id, "status" => "queued", "output" => [] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **kwargs|
      wait_calls << { response_id: response_id, kwargs: kwargs }
      case response_id
      when "resp_1"
        {
          "id" => "resp_1",
          "status" => "completed",
          "output" => [
            {
              "type" => "function_call",
              "name" => "add_and_link_resource",
              "call_id" => "call_90147326",
              "arguments" => {
                resource_type: "applet",
                category: "interactive-diagram",
                description: "Jazz fusion signal chain",
                applet_title: "Signal Chain Explorer",
                applet_code: "function broken( {"
              }.to_json
            }
          ]
        }
      when "resp_2"
        {
          "id" => "resp_2",
          "status" => "completed",
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "{\"suggested_resources\":[]}" }
              ]
            }
          ]
        }
      else
        {
          "id" => "resp_3",
          "status" => "completed",
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "{\"suggested_resources\":[{\"type\":\"Applet\",\"description\":\"Interactive jazz fusion signal chain applet\"}]}"
                }
              ]
            }
          ]
        }
      end
    end
    fake_client.define_singleton_method(:output_text) do |response_hash|
      Array(response_hash["output"]).flat_map do |item|
        next [] unless item["type"] == "message"
        Array(item["content"]).filter_map { |part| part["text"] if part["type"] == "output_text" }
      end.join("\n")
    end

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:execute) do |_function_call|
      {
        type: "function_call_output",
        call_id: "call_90147326",
        output: "Tool execution error: image_token is missing or invalid."
      }
    end
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          ProposeResourcesJob.perform_now(lesson_plan, teacher, source: "teacher_chat_tool")
        end
      end
    end

    assert_equal 3, complete_calls.size
    assert_equal "resp_1", wait_calls.first[:response_id]
    assert_equal "resp_2", wait_calls.second[:response_id]
    assert_equal "resp_3", wait_calls.third[:response_id]

    retry_call = complete_calls.third
    assert_equal "resp_2", retry_call.dig(:kwargs, :previous_response_id)
    assert_includes retry_call.dig(:messages, 0, :content), "One or more tool calls failed"
    assert_includes retry_call.dig(:messages, 0, :content), "image_token is missing or invalid"

    assert_equal "completed", lesson_plan.reload.generation_stage
    assert_equal "Interactive jazz fusion signal chain applet", lesson_plan.suggested_resources.first["Applet"]
  end

  test "propose resources notifies superusers when high tool-call threshold is reached" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    superuser = users(:super_user)
    superuser.create_setting! if superuser.setting.nil?
    app_setting = AppSetting.settings
    app_setting.update!(openai_agent_model: "gpt-5.2")

    tool_calls = Array.new(ProposeResourcesJob::HIGH_TOOL_CALL_WARNING_THRESHOLD + 3) do |idx|
      {
        "type" => "function_call",
        "name" => "exa_search",
        "call_id" => "call_#{idx + 1}",
        "arguments" => { query: "query #{idx + 1}" }.to_json
      }
    end

    complete_calls = []
    wait_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      complete_calls << { messages: messages, kwargs: kwargs }
      response_id = complete_calls.size == 1 ? "resp_1" : "resp_2"
      { "id" => response_id, "status" => "queued", "output" => [] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **kwargs|
      wait_calls << { response_id: response_id, kwargs: kwargs }
      case response_id
      when "resp_1"
        { "id" => "resp_1", "status" => "completed", "output" => tool_calls }
      else
        {
          "id" => "resp_2",
          "status" => "completed",
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "{\"suggested_resources\":[]}" }
              ]
            }
          ]
        }
      end
    end
    fake_client.define_singleton_method(:output_text) { |_response_hash| "{\"suggested_resources\":[]}" }

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:execute) do |function_call|
      { type: "function_call_output", call_id: function_call["call_id"], output: "{\"ok\":true}" }
    end
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    app_setting.update!(log: (app_setting.log || {}).merge("analytics_events" => []))
    OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          ProposeResourcesJob.perform_now(lesson_plan, teacher, source: "teacher_chat_tool")
        end
      end
    end

    assert_equal "resp_1", wait_calls.first[:response_id]
    assert_equal "resp_2", wait_calls.second[:response_id]

    warning_notifications = Notification.where(event_type: "agent_run.high_tool_call_warning", recipient_id: superuser.id)
    assert_equal 1, warning_notifications.count
    warning_notification = warning_notifications.first
    assert_equal "resp_1", warning_notification.params["run_id"]
    assert_equal "resp_1", warning_notification.params["response_id"]
    assert_equal teacher.name, warning_notification.params["teacher_name"]
    assert_equal teacher.id, warning_notification.params["teacher_id"]
    assert_equal "teacher_chat_tool", warning_notification.params["source"]
    assert_equal lesson_plan.id, warning_notification.params["lesson_plan_id"]
    assert_equal 1, warning_notification.params["turns"]
    assert_equal ProposeResourcesJob::HIGH_TOOL_CALL_WARNING_THRESHOLD + 3, warning_notification.params["total_tool_calls"]
    assert_equal ProposeResourcesJob::HIGH_TOOL_CALL_WARNING_THRESHOLD, warning_notification.params["warning_threshold"]

    analytics_events = Array(app_setting.reload.log["analytics_events"])
    analytics_warning_events = analytics_events.select { |entry| entry["event_type"] == "agent_run.high_tool_call_warning" }
    assert_equal 1, analytics_warning_events.size
  end
end

class GenerateLessonPlanPipelineJobTest < ActiveSupport::TestCase
  test "pipeline runs content then resource proposal when requested" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    order = []

    captured_source = nil
    GenerateLessonPlanContentJob.stub(:perform_now, ->(*_args, **_kwargs) { order << :content }) do
      ProposeResourcesJob.stub(:perform_now, ->(*_args, **kwargs) {
        order << :resources
        captured_source = kwargs[:source]
      }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          GenerateLessonPlanPipelineJob.perform_now(
            lesson_plan_id: lesson_plan.id,
            user_id: teacher.id,
            propose_resources: true,
            source: "teacher_chat_tool"
          )
        end
      end
    end

    lesson_plan.reload
    assert_equal [ :content, :resources ], order
    assert_equal "teacher_chat_tool", captured_source
    assert_equal "completed", lesson_plan.generation_stage
  end
end
