require "test_helper"

class ProposeResourcesJobTest < ActiveSupport::TestCase
  test "propose resources updates suggested_resources from responses output" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    app_setting = AppSetting.settings
    openai_api = supported_apis(:openai)
    app_setting.update!(openai_agent_model: "gpt-5.2")
    openai_api.update!(enabled: true, api_access_token: "openai-test-token")

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
          ProposeResourcesJob.perform_now(lesson_plan, teacher)
        end
      end
    end

    lesson_plan.reload
    assert_equal "completed", lesson_plan.generation_stage
    assert_equal "NASA refraction demonstration video", lesson_plan.suggested_resources.first["Video"]
    assert_equal teacher, captured_new_kwargs[:current_user]
    assert_equal openai_api.api_base_uri, captured_new_kwargs[:base_uri]
    assert_equal "openai-test-token", captured_new_kwargs[:access_token]
    assert_equal "gpt-5.2", captured_new_kwargs[:model]
    assert_equal "propose_resources", complete_calls.first.dig(:kwargs, :metadata, :run_type)
    assert_equal true, complete_calls.first.dig(:kwargs, :background)
    assert_equal teacher.id.to_s, complete_calls.first.dig(:kwargs, :metadata, :teacher_id)
    assert_equal lesson_plan.id.to_s, complete_calls.first.dig(:kwargs, :metadata, :lesson_plan_id)
    assert_equal "resp_1", wait_calls.first[:response_id]
  end

  test "propose resources automatically reverts published lesson plan to draft" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    lesson_plan.update!(content: [ { "Intro" => "Ready" } ], status: "published")
    app_setting = AppSetting.settings
    openai_api = supported_apis(:openai)
    app_setting.update!(openai_agent_model: "gpt-5.2")
    openai_api.update!(enabled: true, api_access_token: "openai-test-token")

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
          ProposeResourcesJob.perform_now(lesson_plan, teacher)
        end
      end
    end

    assert_equal "draft", lesson_plan.reload.status
  end
end

class GenerateLessonPlanPipelineJobTest < ActiveSupport::TestCase
  test "pipeline runs content then resource proposal when requested" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    order = []

    GenerateLessonPlanContentJob.stub(:perform_now, ->(*_args, **_kwargs) { order << :content }) do
      ProposeResourcesJob.stub(:perform_now, ->(*_args, **_kwargs) { order << :resources }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          GenerateLessonPlanPipelineJob.perform_now(
            lesson_plan_id: lesson_plan.id,
            user_id: teacher.id,
            propose_resources: true
          )
        end
      end
    end

    lesson_plan.reload
    assert_equal [ :content, :resources ], order
    assert_equal "completed", lesson_plan.generation_stage
  end
end
