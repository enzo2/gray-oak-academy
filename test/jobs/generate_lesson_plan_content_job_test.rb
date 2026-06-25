require "test_helper"

class GenerateLessonPlanContentJobTest < ActiveJob::TestCase
  test "concurrency controls scope to lesson plan id" do
    lesson_plan = Struct.new(:id).new(11)
    user = Struct.new(:id).new(2)

    assert_equal 1, GenerateLessonPlanContentJob.concurrency_limit
    assert_equal 10.minutes, GenerateLessonPlanContentJob.concurrency_duration
    assert_equal "lesson-plan-content-11", GenerateLessonPlanContentJob.concurrency_key.call(lesson_plan, user)
  end

  test "perform updates lesson_plan content and suggested_resources from parsed response" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan

    fake_service = Object.new
    response = {
      "lesson_plan" => [
        { "type" => "activity", "details" => "Warm up activity" },
        { "type" => "explain", "details" => "Explain concept" }
      ],
      "suggested_resources" => [
        { "type" => "book", "description" => "Reference book" }
      ]
    }

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_service }) do
      LlmServiceRouting.stub(:complete_structured_output, response) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
        end
      end
    end

    lesson_plan.reload
    assert_equal "completed", lesson_plan.generation_stage
    assert_includes lesson_plan.content, { "activity" => "Warm up activity" }
    assert_includes lesson_plan.content, { "explain" => "Explain concept" }
    assert_equal [ { "book" => "Reference book" } ], lesson_plan.suggested_resources
  end

  test "perform appends steering guidance to prompt when provided" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    captured_messages = nil

    fake_service = Object.new
    response = {
      "lesson_plan" => [
        { "type" => "activity", "details" => "Warm up activity" }
      ],
      "suggested_resources" => []
    }

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_service }) do
      LlmServiceRouting.stub(:complete_structured_output, ->(**kwargs) {
        captured_messages = kwargs[:messages]
        response
      }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          assert GenerateLessonPlanContentJob.perform_now(
            lesson_plan,
            teacher,
            steering_guidance: "Prefer a walk-and-talk discussion with minimal chalkboard use."
          )
        end
      end
    end

    assert_includes captured_messages.first[:content], "Additional steering from the supervising teacher for this run:"
    assert_includes captured_messages.first[:content], "Prefer a walk-and-talk discussion with minimal chalkboard use."
  end

  test "perform enables native web search on an OpenAI Responses host and the prompt carries grounding guidance" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    captured_client_kwargs = nil
    captured_messages = nil
    response = { "lesson_plan" => [ { "type" => "activity", "details" => "Warm up" } ], "suggested_resources" => [] }

    LlmServiceRouting.stub(:effective_llm_api_host_for, "api.openai.com") do
      LlmServiceRouting.stub(:build_completion_client, ->(**kwargs) { captured_client_kwargs = kwargs; Object.new }) do
        LlmServiceRouting.stub(:complete_structured_output, ->(**kwargs) { captured_messages = kwargs[:messages]; response }) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
          end
        end
      end
    end

    assert_equal [ { type: "web_search" } ], captured_client_kwargs[:provider_native_tools]
    assert_includes captured_messages.first[:content], "If web search is available for this run"
    assert_includes captured_messages.first[:content], "Do not use search to fetch, link, download, or save resources"
  end

  test "perform enables native web search on the Codex (chatgpt.com) Responses host" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    captured_client_kwargs = nil
    response = { "lesson_plan" => [ { "type" => "activity", "details" => "Warm up" } ], "suggested_resources" => [] }

    LlmServiceRouting.stub(:effective_llm_api_host_for, "chatgpt.com") do
      LlmServiceRouting.stub(:build_completion_client, ->(**kwargs) { captured_client_kwargs = kwargs; Object.new }) do
        LlmServiceRouting.stub(:complete_structured_output, response) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
          end
        end
      end
    end

    assert_equal [ { type: "web_search" } ], captured_client_kwargs[:provider_native_tools]
  end

  test "perform uses OpenRouter native web search tool name" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    captured_client_kwargs = nil
    captured_messages = nil
    response = { "lesson_plan" => [ { "type" => "activity", "details" => "Warm up" } ], "suggested_resources" => [] }

    LlmServiceRouting.stub(:effective_llm_api_host_for, "openrouter.ai") do
      LlmServiceRouting.stub(:build_completion_client, ->(**kwargs) { captured_client_kwargs = kwargs; Object.new }) do
        LlmServiceRouting.stub(:complete_structured_output, ->(**kwargs) { captured_messages = kwargs[:messages]; response }) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
          end
        end
      end
    end

    assert_equal [ { type: "openrouter:web_search" } ], captured_client_kwargs[:provider_native_tools]
  end

  test "perform enables native web search on the xAI (api.x.ai) Responses host" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    captured_client_kwargs = nil
    response = { "lesson_plan" => [ { "type" => "activity", "details" => "Warm up" } ], "suggested_resources" => [] }

    LlmServiceRouting.stub(:effective_llm_api_host_for, "api.x.ai") do
      LlmServiceRouting.stub(:build_completion_client, ->(**kwargs) { captured_client_kwargs = kwargs; Object.new }) do
        LlmServiceRouting.stub(:complete_structured_output, response) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
          end
        end
      end
    end

    assert_equal [ { type: "web_search" } ], captured_client_kwargs[:provider_native_tools]
  end

  test "perform does not enable web search on hosts without a known search tool" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    captured_client_kwargs = nil
    captured_messages = nil
    response = { "lesson_plan" => [ { "type" => "activity", "details" => "Warm up" } ], "suggested_resources" => [] }

    LlmServiceRouting.stub(:effective_llm_api_host_for, "example.com") do
      LlmServiceRouting.stub(:build_completion_client, ->(**kwargs) { captured_client_kwargs = kwargs; Object.new }) do
        LlmServiceRouting.stub(:complete_structured_output, ->(**kwargs) { captured_messages = kwargs[:messages]; response }) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
          end
        end
      end
    end

    assert_nil captured_client_kwargs[:provider_native_tools]
  end

  test "perform builds revision context from existing content and steering guidance" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    lesson_plan.update!(
      content: [ { "Knowledge" => "Explain equivalent fractions with visual models." } ],
      suggested_resources: [ { "Manipulative" => "Fraction strips or fraction circles." } ],
      generation_stage: "completed"
    )
    captured_messages = nil

    fake_service = Object.new
    response = {
      "lesson_plan" => [
        { "type" => "activity", "details" => "Use fraction strips to compare thirds and sixths." }
      ],
      "suggested_resources" => []
    }
    prompt = "Create or revise this lesson.\n{revision_context}\nLinked resources: {linked_resources}"

    Prompt.stub(:get_prompt, prompt) do
      LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_service }) do
        LlmServiceRouting.stub(:complete_structured_output, ->(**kwargs) {
          captured_messages = kwargs[:messages]
          response
        }) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            assert GenerateLessonPlanContentJob.perform_now(
              lesson_plan,
              teacher,
              steering_guidance: "Add a hands-on formative check."
            )
          end
        end
      end
    end

    prompt_content = captured_messages.first[:content]
    assert_includes prompt_content, "Current saved lesson plan JSON:"
    assert_includes prompt_content, '"type": "Knowledge"'
    assert_includes prompt_content, '"details": "Explain equivalent fractions with visual models."'
    assert_includes prompt_content, '"type": "Manipulative"'
    assert_includes prompt_content, '"description": "Fraction strips or fraction circles."'
    assert_includes prompt_content, "Revision instruction from the supervising teacher:"
    assert_includes prompt_content, "Add a hands-on formative check."
    assert_includes prompt_content, "Return the full updated lesson_plan array"
    refute_includes prompt_content, "Additional steering from the supervising teacher for this run:"
  end

  test "perform replaces existing content (no revision) when called without steering guidance" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    lesson_plan.update!(
      content: [ { "Knowledge" => "Old explanation to be replaced." } ],
      generation_stage: "completed"
    )
    captured_messages = nil
    response = {
      "lesson_plan" => [ { "type" => "activity", "details" => "Fresh generated content." } ],
      "suggested_resources" => []
    }

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { Object.new }) do
      LlmServiceRouting.stub(:complete_structured_output, ->(**kwargs) { captured_messages = kwargs[:messages]; response }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
        end
      end
    end

    # No revision instruction -> replace, not revise (preserves TeacherAgent contract).
    refute_includes captured_messages.first[:content], "Current saved lesson plan JSON:"
    refute_includes captured_messages.first[:content], "Revision instruction from the supervising teacher:"
    assert_equal [ { "activity" => "Fresh generated content." } ], lesson_plan.reload.content
  end

  test "perform records de-duplicated searches and cited sources from the web search response" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    response = { "lesson_plan" => [ { "type" => "activity", "details" => "Warm up" } ], "suggested_resources" => [] }

    fake_client = Object.new
    fake_client.define_singleton_method(:last_response_hash) do
      {
        "output" => [
          { "type" => "web_search_call", "action" => { "type" => "search", "query" => "current NGSS fractions standards" } },
          { "type" => "web_search_call", "action" => { "type" => "search", "query" => "current NGSS fractions standards" } },
          { "type" => "message", "content" => [ {
            "type" => "output_text", "text" => "{}",
            "annotations" => [
              { "type" => "url_citation", "url" => "https://example.com/a", "title" => "Source A" },
              { "type" => "url_citation", "url" => "https://example.com/a", "title" => "Source A" }
            ]
          } ] }
        ]
      }
    end

    LlmServiceRouting.stub(:effective_llm_api_host_for, "api.openai.com") do
      LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_client }) do
        LlmServiceRouting.stub(:complete_structured_output, response) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
          end
        end
      end
    end

    lesson_plan.reload
    assert_equal [ "current NGSS fractions standards" ], lesson_plan.generation_searches
    assert_equal [ { "url" => "https://example.com/a", "title" => "Source A" } ], lesson_plan.generation_sources
  end

  test "perform folds xAI top-level citations into sources, de-duplicated with annotations" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    response = { "lesson_plan" => [ { "type" => "activity", "details" => "Warm up" } ], "suggested_resources" => [] }

    fake_client = Object.new
    fake_client.define_singleton_method(:last_response_hash) do
      {
        "output" => [
          { "type" => "message", "content" => [ {
            "type" => "output_text", "text" => "{}",
            "annotations" => [
              { "type" => "url_citation", "url" => "https://x.ai/news", "title" => "xAI News" }
            ]
          } ] }
        ],
        # xAI also returns a top-level citations array of plain URL strings.
        "citations" => [
          "https://x.ai/news",
          "https://x.ai/news",
          "https://docs.x.ai/developers/release-notes"
        ]
      }
    end

    LlmServiceRouting.stub(:effective_llm_api_host_for, "api.x.ai") do
      LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_client }) do
        LlmServiceRouting.stub(:complete_structured_output, response) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
          end
        end
      end
    end

    lesson_plan.reload
    assert_empty lesson_plan.generation_searches
    # Annotation (titled) wins the dedup; the new top-level citation is url-only.
    assert_equal(
      [
        { "url" => "https://x.ai/news", "title" => "xAI News" },
        { "url" => "https://docs.x.ai/developers/release-notes", "title" => nil }
      ],
      lesson_plan.generation_sources
    )
  end

  test "failure broadcast renders generation controls without a Warden request" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    replace_call = nil

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { raise OpenAiError, "provider unavailable" }) do
      Turbo::StreamsChannel.stub(:broadcast_append_to, true) do
        Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*args, **kwargs) {
          replace_call = { args: args, kwargs: kwargs }
        }) do
          assert_equal false, GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
        end
      end
    end

    lesson_plan.reload
    assert_equal "failed", lesson_plan.generation_stage
    assert_includes lesson_plan.generation_error, "provider unavailable"
    assert_equal teacher, replace_call.dig(:kwargs, :locals, :current_user)

    html = ApplicationController.render(
      partial: replace_call.dig(:kwargs, :partial),
      locals: replace_call.dig(:kwargs, :locals)
    )
    assert_includes html, "lesson-plan-generation-controls"
  end
end
