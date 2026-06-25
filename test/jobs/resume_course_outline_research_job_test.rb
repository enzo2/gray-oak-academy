require "test_helper"

class ResumeCourseOutlineResearchJobTest < ActiveSupport::TestCase
  test "resumes stored response id and applies updates through flow tools" do
    teacher = users(:admin)
    course = courses(:one)
    course.update!(
      summary: "Original summary",
      outline: [ { "Topic 1" => "Old details" } ],
      outline_research_stage: "awaiting_teacher_input",
      outline_guidance_report_md: "Original report",
      outline_guidance_questions: [
        {
          "id" => "q1",
          "question" => "Keep current tone?",
          "choices" => {
            "A" => "Keep tone as-is",
            "B" => "Tighten tone and emphasize evidence",
            "C" => "Blend current tone with a clearer structure",
            "OTHER" => "Another direction"
          }
        }
      ],
      outline_guidance_answers: {
        "q1" => { "choice" => "B" },
        "_additional_comments" => "Tighten tone and add one local source."
      },
      outline_research: {
        "source_anchors" => [
          { "id" => "anchor_1", "title" => "Source A", "url" => "https://example.com/a", "excerpt" => "", "highlights" => [], "notes" => "" }
        ],
        "coverage_gaps" => [],
        "factual_notes" => [],
        "alternative_approaches" => [],
        "apply_agent_summary_md" => "Old completion summary",
        "apply_completed_at" => "2020-01-01T00:00:00Z"
      },
      outline_research_run_id: "run_123",
      outline_research_response_id: "resp_previous",
      course_prior_state: {}
    )

    AgentRun.create!(
      run_id: "run_123",
      response_id: "resp_previous",
      provider_base_uri: SupportedApi::OPENAI_BASE_URI
    )

    ensure_prompt("apply_course_outline_research", "Teacher responses:\n{teacher_answers}\nAdditional comments:\n{additional_comments}")

    complete_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:base_uri) { SupportedApi::OPENAI_BASE_URI }
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      complete_calls << { messages: messages, kwargs: kwargs }
      id = complete_calls.length == 1 ? "resp_apply_1" : "resp_apply_2"
      { "id" => id }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **_kwargs|
      case response_id
      when "resp_apply_1"
        {
          "id" => "resp_apply_1",
          "status" => "completed",
          "output" => [
            {
              "type" => "function_call",
              "name" => "apply_course_research_update",
              "call_id" => "call_apply_1",
              "arguments" => {
                summary: "Updated summary",
                outline: [ { topic: "Updated Topic", description: "Updated details" } ],
                outline_guidance_report_md: "Updated report",
                outline_research: {
                  "source_anchors" => [
                    { "id" => "anchor_1", "title" => "Source A", "url" => "https://example.com/a", "excerpt" => "", "highlights" => [], "notes" => "" }
                  ],
                  "coverage_gaps" => [ "Add local case study" ],
                  "factual_notes" => [],
                  "alternative_approaches" => []
                }
              }.to_json
            }
          ]
        }
      when "resp_apply_2"
        {
          "id" => "resp_apply_2",
          "status" => "completed",
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "Applied successfully." }
              ]
            }
          ]
        }
      else
        raise "Unexpected response id: #{response_id}"
      end
    end

    captured_new_kwargs = nil
    OpenaiResponsesService.stub(:for_agent_run, ->(**kwargs) { captured_new_kwargs = kwargs; fake_client }) do
      emitted_events = []
      job = ResumeCourseOutlineResearchJob.new
      job.stub(:emit_analytics_event, ->(event_class, **_kwargs) { emitted_events << event_class }) do
        CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
          job.perform(
            course_id: course.id,
            user_id: teacher.id,
            permission_granted: true,
            source: "course_edit_page"
          )
        end
      end
      assert_includes emitted_events, Events::CourseOutlineResearchApplyCompleted
    end

    course.reload
    assert_equal "completed", course.outline_research_stage
    assert_equal "Updated summary", course.summary
    assert_equal [ { "Updated Topic" => "Updated details" } ], course.outline
    assert_equal "Updated report", course.outline_guidance_report_md
    assert_equal "resp_apply_2", course.outline_research_response_id
    assert_equal "Original summary", course.course_prior_state["summary"]
    assert_equal "Applied successfully.", course.outline_research_hash["apply_agent_summary_md"]
    assert_predicate course.outline_research_hash["apply_completed_at"].to_s, :present?
    assert_not_equal "2020-01-01T00:00:00Z", course.outline_research_hash["apply_completed_at"].to_s

    assert_equal "resp_previous", complete_calls.first.dig(:kwargs, :previous_response_id)
    assert_includes complete_calls.first.dig(:messages, 0, :content), "Choice B: Tighten tone and emphasize evidence."
    assert_includes complete_calls.first.dig(:messages, 0, :content), "Additional comments:"
    assert_includes complete_calls.first.dig(:messages, 0, :content), "Tighten tone and add one local source."
    assert_equal teacher, captured_new_kwargs[:user]
    assert_equal false, captured_new_kwargs[:agent_run_require_stateful]
    assert_nil captured_new_kwargs[:base_uri]
    assert_nil captured_new_kwargs[:access_token]
    assert_nil captured_new_kwargs[:model]
  end

  test "does not reuse a response id from a different provider" do
    AgentRun.create!(
      run_id: "run_provider_affinity",
      response_id: "resp_openai",
      provider_base_uri: SupportedApi::OPENAI_BASE_URI
    )
    client = Struct.new(:base_uri).new(SupportedApi::XAI_BASE_URI)

    response_id = ResumeCourseOutlineResearchJob.new.send(
      :reusable_previous_response_id,
      client: client,
      response_id: "resp_openai"
    )

    assert_nil response_id
  end

  test "fails when prerequisites are not met" do
    teacher = users(:admin)
    course = courses(:one)
    course.update!(
      outline_research_stage: "awaiting_teacher_input",
      outline_guidance_questions: [ { "id" => "q1", "question" => "Question?" } ],
      outline_guidance_answers: {},
      outline_research: {
        "source_anchors" => [
          { "id" => "anchor_1" }
        ]
      },
      outline_research_response_id: "resp_previous"
    )

    error = assert_raises(OpenAiError) do
      CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
        ResumeCourseOutlineResearchJob.perform_now(
          course_id: course.id,
          user_id: teacher.id,
          permission_granted: true,
          source: "course_edit_page"
        )
      end
    end

    assert_includes error.message, "must be answered"
    assert_equal "failed", course.reload.outline_research_stage
    assert_includes course.outline_research_error.to_s, "Failed to apply outline research guidance"
  end

  test "transient OAuth failures keep guidance application in progress" do
    teacher = users(:admin)
    course = courses(:one)
    course.update!(
      outline_research_stage: "awaiting_teacher_input",
      outline_guidance_questions: [],
      outline_guidance_answers: {},
      outline_research: {
        "source_anchors" => [],
        "coverage_gaps" => [],
        "factual_notes" => [],
        "alternative_approaches" => []
      }
    )
    transient_error = BackgroundAgentConfigResolver::TransientOauthError.new("temporary OAuth failure")
    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }

    CourseResearchToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
      OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { raise transient_error }) do
        CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
          job = ResumeCourseOutlineResearchJob.new
          assert_raises(BackgroundAgentConfigResolver::TransientOauthError) do
            job.perform(course_id: course.id, user_id: teacher.id, permission_granted: true)
          end
        end
      end
    end

    course.reload
    assert_equal "applying_guidance_updates", course.outline_research_stage
    assert_nil course.outline_research_error
  end

  test "codex usage limit re-runs guidance application on the shared provider" do
    teacher = users(:admin)
    course = courses(:one)
    AppSetting.settings.update!(
      background_agent_model: "gpt-5.2",
      background_agent_supported_api_id: supported_apis(:openai).id
    )
    course.update!(
      outline_research_stage: "awaiting_teacher_input",
      outline_guidance_questions: [],
      outline_guidance_answers: {},
      outline_research: {
        "source_anchors" => [],
        "coverage_gaps" => [],
        "factual_notes" => [],
        "alternative_approaches" => []
      }
    )
    usage_limit_error = BackgroundAgentConfigResolver::CodexUsageLimitError.new("The usage limit has been reached")
    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    enqueued = []

    CourseResearchToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
      OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { raise usage_limit_error }) do
        ResumeCourseOutlineResearchJob.stub(:perform_later, ->(**kwargs) { enqueued << kwargs }) do
          CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
            ResumeCourseOutlineResearchJob.new.perform(course_id: course.id, user_id: teacher.id, permission_granted: true)
          end
        end
      end
    end

    assert_equal 1, enqueued.size
    assert_equal true, enqueued.first[:skip_user_codex]
    assert_equal course.id, enqueued.first[:course_id]
    assert_equal true, enqueued.first[:permission_granted]

    course.reload
    assert_equal "applying_guidance_updates", course.outline_research_stage
    assert_nil course.outline_research_error
  end

  test "uses development stub apply phase when enabled" do
    teacher = users(:admin)
    course = courses(:one)
    course.update!(
      summary: "Original summary",
      outline: [ { "Topic 1" => "Old details" } ],
      outline_research_stage: "awaiting_teacher_input",
      outline_guidance_questions: [
        {
          "id" => "q1",
          "question" => "Question one?",
          "choices" => { "A" => "A", "B" => "B", "C" => "C", "OTHER" => "Other" }
        }
      ],
      outline_guidance_answers: {
        "q1" => { "choice" => "A" }
      },
      outline_research: {
        "source_anchors" => [
          { "id" => "anchor_1", "title" => "Source A", "url" => "https://example.com/a", "excerpt" => "", "highlights" => [], "notes" => "" }
        ],
        "coverage_gaps" => [],
        "factual_notes" => [],
        "alternative_approaches" => []
      },
      outline_research_run_id: "run_stub_1",
      outline_research_response_id: "resp_stub_previous",
      course_prior_state: {}
    )

    CourseOutlineResearchStubService.stub(:enabled?, true) do
      OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { raise "Responses API should not run in stub mode" }) do
        CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
          ResumeCourseOutlineResearchJob.perform_now(
            course_id: course.id,
            user_id: teacher.id,
            permission_granted: true,
            source: "teacher_chat_tool"
          )
        end
      end
    end

    course.reload
    assert_equal "completed", course.outline_research_stage
    assert_predicate course.outline_research_hash["apply_agent_summary_md"].to_s, :present?
    assert_predicate course.outline_research_hash["apply_completed_at"].to_s, :present?
    assert_predicate course.course_prior_state, :present?
    assert_match(/stub_apply_resp_/, course.outline_research_response_id.to_s)
    assert_predicate course.summary.to_s, :present?
    assert_operator course.outline.size, :>, 0
  end

  test "marks the agent run failed when apply tool-turn limit is exceeded" do
    teacher = users(:admin)
    course = courses(:one)
    course.update!(
      outline_research_stage: "awaiting_teacher_input",
      outline_guidance_questions: [
        {
          "id" => "q1",
          "question" => "Question one?",
          "choices" => { "A" => "A", "B" => "B", "C" => "C", "OTHER" => "Other" }
        }
      ],
      outline_guidance_answers: { "q1" => { "choice" => "A" } },
      outline_research: {
        "source_anchors" => [
          { "id" => "anchor_1", "title" => "Source A", "url" => "https://example.com/a", "excerpt" => "", "highlights" => [], "notes" => "" }
        ],
        "coverage_gaps" => [],
        "factual_notes" => [],
        "alternative_approaches" => []
      },
      outline_research_run_id: "run_limit_1",
      outline_research_response_id: "resp_previous"
    )
    ensure_prompt("apply_course_outline_research", "Teacher responses:\n{teacher_answers}")
    AppSetting.settings.update!(background_agent_model: "gpt-5.2", background_agent_max_tool_turns: "1")

    complete_calls = 0
    failure_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |_messages = nil, **_kwargs|
      complete_calls += 1
      { "id" => "resp_apply_#{complete_calls}" }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **_kwargs|
      {
        "id" => response_id,
        "status" => "completed",
        "output" => [
          {
            "type" => "function_call",
            "name" => "apply_course_research_update",
            "call_id" => "call_#{response_id}",
            "arguments" => {
              summary: "Updated summary",
              outline: [ { topic: "Updated Topic", description: "Updated details" } ]
            }.to_json
          }
        ]
      }
    end
    fake_client.define_singleton_method(:mark_current_agent_run_failed) do |error_message:, response_hash:|
      failure_calls << { error_message: error_message, response_hash: response_hash }
    end

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:execute) do |function_call|
      { type: "function_call_output", call_id: function_call["call_id"], output: "{\"ok\":true}" }
    end

    OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { fake_client }) do
      CourseResearchToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        error = assert_raises(OpenAiError) do
          CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
            ResumeCourseOutlineResearchJob.perform_now(
              course_id: course.id,
              user_id: teacher.id,
              permission_granted: true,
              source: "course_edit_page"
            )
          end
        end
        assert_includes error.message, "Outline research apply run exceeded tool-call limit (1)"
      end
    end

    assert_equal "failed", course.reload.outline_research_stage
    assert_equal 1, failure_calls.size
    assert_includes failure_calls.first[:error_message], "Outline research apply run exceeded tool-call limit (1)"
    assert_equal "resp_apply_2", failure_calls.first[:response_hash]["id"]
  end

  test "stateless provider resumes from persisted artifacts without a previous response id" do
    teacher = users(:admin)
    course = courses(:one)
    course.update!(
      summary: "Original summary",
      outline: [ { "Original" => "Details" } ],
      outline_research_stage: "awaiting_teacher_input",
      outline_guidance_report_md: "Use inquiry learning.",
      outline_guidance_questions: [],
      outline_guidance_answers: {},
      outline_research: { "source_anchors" => [], "coverage_gaps" => [], "factual_notes" => [], "alternative_approaches" => [] },
      outline_research_run_id: "run_stateless_resume",
      outline_research_response_id: nil,
      course_prior_state: {}
    )
    ensure_prompt("apply_course_outline_research", "Report: {outline_guidance_report_md}\nOutline: {outline}\nAnswers: {teacher_answers}")
    responses = [
      {
        "id" => "resp_stateless_apply_1", "status" => "completed", "usage" => { "input_tokens" => 20 },
        "output" => [
          { "type" => "reasoning", "content" => "plan update", "format" => "unknown" },
          {
            "type" => "function_call", "id" => "fc_apply", "name" => "apply_course_research_update", "call_id" => "call_apply",
            "arguments" => { summary: "Updated stateless summary", outline: [ { topic: "Inquiry", description: "Lab" } ] }.to_json
          }
        ]
      },
      {
        "id" => "resp_stateless_apply_2", "status" => "completed", "usage" => { "input_tokens" => 40 },
        "output" => [ { "type" => "message", "content" => [ { "type" => "output_text", "text" => "Applied from artifacts." } ] } ]
      }
    ]
    complete_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:stateful_supported?) { false }
    fake_client.define_singleton_method(:model) { "moonshotai/kimi-k2.6" }
    fake_client.define_singleton_method(:base_uri) { SupportedApi::OPENROUTER_BASE_URI }
    fake_client.define_singleton_method(:last_input_items) { @last_input_items.deep_dup }
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      complete_calls << { messages: messages, kwargs: kwargs }
      @last_input_items = if messages.present?
        [ { "role" => "developer", "content" => "system" }, { "role" => "user", "content" => messages.first[:content] } ]
      else
        kwargs.fetch(:input).deep_dup
      end
      { "id" => responses.fetch(complete_calls.size - 1)["id"] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **_kwargs|
      responses.find { |response| response["id"] == response_id }
    end
    fake_client.define_singleton_method(:mark_current_agent_run_failed) { |**_kwargs| nil }

    OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { fake_client }) do
      CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
        ResumeCourseOutlineResearchJob.perform_now(
          course_id: course.id,
          user_id: teacher.id,
          permission_granted: true,
          source: "course_edit_page"
        )
      end
    end

    course.reload
    assert_equal "completed", course.outline_research_stage
    assert_equal "Updated stateless summary", course.summary
    assert_equal "Applied from artifacts.", course.outline_research_hash["apply_agent_summary_md"]
    assert_nil complete_calls.first.dig(:kwargs, :previous_response_id)
    assert_nil complete_calls.second.dig(:kwargs, :previous_response_id)
    assert_includes complete_calls.first.dig(:messages, 0, :content), "Use inquiry learning."
  end

  private

  def ensure_prompt(category, text)
    Prompt.find_or_create_by!(category: category, teacher_id: nil) do |prompt|
      prompt.title = category.humanize
      prompt.prompt = text
    end
  end
end
