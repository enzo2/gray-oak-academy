require "test_helper"

class EnrichCourseOutlineJobTest < ActiveSupport::TestCase
  test "stores research artifacts and guidance questions then awaits teacher input" do
    teacher = users(:admin)
    course = courses(:one)
    conversation = conversations(:teacher_generic_conversation)
    course.update!(outline: [ { "Origins" => "How the city began" } ])

    ensure_prompt("research_course_outline", "Title: {title}\nSummary: {summary}\nOutline: {outline}")
    ensure_prompt("analyze_course_outline_research", "Course: {title}\nResearch: {outline_research}")

    exa_response = {
      "id" => "search_1",
      "output" => {
        "content" => {
          "sourceAnchors" => [
            {
              "title" => "Primary Source",
              "sourceUrl" => "https://example.com/source",
              "summary" => "Useful excerpt",
              "keyPoints" => [ "Key point" ],
              "note" => "Use for context"
            }
          ],
          "coverageGaps" => [ "Local perspective" ],
          "factualNotes" => [ "Verify chronology in unit 2" ],
          "alternativeApproaches" => [ "Theme-first sequence" ]
        },
        "grounding" => {
          "sources" => [ { "url" => "https://example.com/source" } ]
        }
      }
    }

    guidance_json = {
      report_markdown: "## Guidance\nTighten chronology and add local context.",
      research_questions: [
        { id: "q1", question: "Should local history be mandatory?", choices: { a: "Yes, mandatory", b: "Optional extension", c: "Blend with core units", other: "Custom policy" } },
        { id: "q1", question: "Keep chronology-first sequencing?", choices: { a: "Keep chronology-first", b: "Switch to theme-first", c: "Hybrid sequence", other: "Another sequence" } },
        { id: "q3", question: "Prioritize primary sources?", choices: { a: "High priority", b: "Moderate priority", c: "Targeted use", other: "Custom source strategy" } },
        { id: "q4", question: "Add project checkpoint?", choices: { a: "Add one checkpoint", b: "Add multiple checkpoints", c: "Single final checkpoint", other: "Custom checkpoint plan" } },
        { id: "q5", question: "Adjust pacing in week 1?", choices: { a: "Keep pace", b: "Slow down", c: "Accelerate", other: "Custom pacing" } },
        { id: "q6", question: "This sixth question should be trimmed.", choices: { a: "A", b: "B", c: "C", other: "Other" } }
      ]
    }.to_json

    captured_exa = {}
    fake_exa = Object.new
    fake_exa.define_singleton_method(:deep_research) do |query:, output_schema:|
      captured_exa[:query] = query
      captured_exa[:output_schema] = output_schema
      exa_response
    end

    captured_responses = {}
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |_messages = nil, **kwargs|
      captured_responses[:background] = kwargs[:background]
      { "id" => "resp_guidance_1" }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **_kwargs|
      captured_responses[:response_id] = response_id
      {
        "id" => "resp_guidance_1",
        "status" => "completed",
        "output" => [
          {
            "type" => "message",
            "content" => [
              {
                "type" => "output_text",
                "text" => guidance_json
              }
            ]
          }
        ]
      }
    end
    fake_client.define_singleton_method(:output_text) { |_response_hash| guidance_json }

    captured_new_kwargs = nil
    ExaApiService.stub(:new, ->(**_kwargs) { fake_exa }) do
      OpenaiResponsesService.stub(:for_agent_run, ->(**kwargs) { captured_new_kwargs = kwargs; fake_client }) do
        emitted_events = []
        chalkboard_broadcasts = []
        job = EnrichCourseOutlineJob.new
        job.stub(:emit_analytics_event, ->(event_class, **_kwargs) { emitted_events << event_class }) do
          CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
            Turbo::StreamsChannel.stub(:broadcast_append_to, ->(*args, **kwargs) {
              chalkboard_broadcasts << { args: args, kwargs: kwargs }
            }) do
              job.perform(
                course_id: course.id,
                user_id: teacher.id,
                source: "course_edit_page",
                conversation_id: conversation.id
              )
            end
          end
        end
        assert_includes emitted_events, Events::CourseOutlineResearchExaCompleted
        assert_includes emitted_events, Events::CourseOutlineResearchGuidanceReady
        assert_equal 1, chalkboard_broadcasts.size

        broadcast = chalkboard_broadcasts.first
        assert_equal "conversation_#{conversation.id}", broadcast[:args].first
        assert_equal "chalkboard_tab_inbox", broadcast.dig(:kwargs, :target)
        assert_equal "shared/chalkboard_tab_event", broadcast.dig(:kwargs, :partial)
        payload = broadcast.dig(:kwargs, :locals, :payload)
        assert_equal "open_push_tab", payload[:event_type]
        assert_equal "Outline Research", payload[:tab_title]
        assert_includes payload[:content_html], "Outline Research Ready"
      end
    end

    course.reload
    assert_equal "awaiting_teacher_input", course.outline_research_stage
    assert_equal "resp_guidance_1", course.outline_research_response_id
    assert course.outline_research_run_id.present?
    assert_equal "https://example.com/source", course.outline_research.dig("source_anchors", 0, "url")
    assert_equal "Useful excerpt", course.outline_research.dig("source_anchors", 0, "excerpt")
    assert_equal [ "Key point" ], course.outline_research.dig("source_anchors", 0, "highlights")
    assert_equal "search_1", course.outline_research.dig("exa_research", "research_id")
    assert_equal "completed", course.outline_research.dig("exa_research", "status")
    assert_equal "search", course.outline_research.dig("exa_research", "api")
    assert_equal "deep-reasoning", course.outline_research.dig("exa_research", "type")
    assert_equal [ { "url" => "https://example.com/source" } ], course.outline_research.dig("exa_research", "grounding", "sources")
    assert_equal "## Guidance\nTighten chronology and add local context.", course.outline_guidance_report_md
    assert_equal 5, course.outline_guidance_questions.size
    assert_equal "q1", course.outline_guidance_questions.first["id"]
    assert_equal "q1_2", course.outline_guidance_questions.second["id"]
    assert_equal course.outline_guidance_questions.size, course.outline_guidance_questions.map { |q| q["id"] }.uniq.size
    assert_equal "Yes, mandatory", course.outline_guidance_questions.first.dig("choices", "A")
    assert_equal "Custom policy", course.outline_guidance_questions.first.dig("choices", "OTHER")
    assert_includes captured_exa[:query], "Title:"
    assert captured_exa[:output_schema][:properties].key?(:source_anchors)
    assert_equal true, captured_responses[:background]
    assert_equal "resp_guidance_1", captured_responses[:response_id]
    assert_equal teacher, captured_new_kwargs[:user]
    assert_equal false, captured_new_kwargs[:agent_run_require_stateful]
    assert_nil captured_new_kwargs[:base_uri]
    assert_nil captured_new_kwargs[:access_token]
    assert_nil captured_new_kwargs[:model]
  end

  test "does not broadcast chalkboard notification when conversation_id is blank" do
    job = EnrichCourseOutlineJob.new
    course = courses(:one)
    called = false

    Turbo::StreamsChannel.stub(:broadcast_append_to, ->(*_args, **_kwargs) { called = true }) do
      job.send(:broadcast_chalkboard_research_input, course: course, conversation_id: nil)
    end

    assert_equal false, called
  end

  test "reuses completed Exa research when guidance generation is retried" do
    teacher = users(:admin)
    course = courses(:one)
    course.update!(
      outline: [ { "Origins" => "How the city began" } ],
      outline_research_stage: "failed",
      outline_research: {
        "source_anchors" => [ { "id" => "anchor_1", "url" => "https://example.com/source" } ],
        "coverage_gaps" => [],
        "factual_notes" => [],
        "alternative_approaches" => [],
        "research_id" => "research_existing",
        "exa_research" => { "research_id" => "research_existing", "status" => "completed" }
      }
    )
    ensure_prompt("analyze_course_outline_research", "Course: {title}\nResearch: {outline_research}")

    guidance_json = {
      report_markdown: "## Guidance\nReuse the completed research.",
      research_questions: [ { id: "q1", question: "Keep the current scope?" } ]
    }.to_json
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) { |_messages = nil, **_kwargs| { "id" => "resp_retry" } }
    fake_client.define_singleton_method(:wait_for_response) do |_response_id, **_kwargs|
      { "id" => "resp_retry", "status" => "completed", "output" => [] }
    end
    fake_client.define_singleton_method(:output_text) { |_response_hash| guidance_json }

    ExaApiService.stub(:new, ->(**_kwargs) { flunk("completed Exa research should be reused") }) do
      OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { fake_client }) do
        CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
          job = EnrichCourseOutlineJob.new
          job.stub(:emit_analytics_event, true) do
            job.perform(course_id: course.id, user_id: teacher.id)
          end
        end
      end
    end

    course.reload
    assert_equal "awaiting_teacher_input", course.outline_research_stage
    assert_equal "research_existing", course.outline_research["research_id"]
    assert_equal "resp_retry", course.outline_research_response_id
  end

  test "transient OAuth failures keep guidance generation in progress" do
    teacher = users(:admin)
    course = courses(:one)
    course.update!(
      outline_research_stage: "failed",
      outline_research: {
        "source_anchors" => [ { "id" => "anchor_1", "url" => "https://example.com/source" } ],
        "coverage_gaps" => [],
        "factual_notes" => [],
        "alternative_approaches" => [],
        "exa_research" => { "research_id" => "research_existing", "status" => "completed" }
      }
    )
    transient_error = BackgroundAgentConfigResolver::TransientOauthError.new("temporary OAuth failure")
    job = EnrichCourseOutlineJob.new

    job.stub(:generate_guidance_questions, ->(**_kwargs) { raise transient_error }) do
      job.stub(:emit_analytics_event, true) do
        CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
          assert_raises(BackgroundAgentConfigResolver::TransientOauthError) do
            job.perform(course_id: course.id, user_id: teacher.id)
          end
        end
      end
    end

    course.reload
    assert_equal "generating_guidance_questions", course.outline_research_stage
    assert_nil course.outline_research_error
  end

  test "codex usage limit re-runs guidance generation on the shared provider" do
    teacher = users(:admin)
    course = courses(:one)
    AppSetting.settings.update!(
      background_agent_model: "gpt-5.2",
      background_agent_supported_api_id: supported_apis(:openai).id
    )
    course.update!(
      outline_research_stage: "failed",
      outline_research: {
        "source_anchors" => [ { "id" => "anchor_1", "url" => "https://example.com/source" } ],
        "coverage_gaps" => [],
        "factual_notes" => [],
        "alternative_approaches" => [],
        "exa_research" => { "research_id" => "research_existing", "status" => "completed" }
      }
    )
    usage_limit_error = BackgroundAgentConfigResolver::CodexUsageLimitError.new("The usage limit has been reached")
    job = EnrichCourseOutlineJob.new
    enqueued = []

    job.stub(:generate_guidance_questions, ->(**_kwargs) { raise usage_limit_error }) do
      job.stub(:emit_analytics_event, true) do
        EnrichCourseOutlineJob.stub(:perform_later, ->(**kwargs) { enqueued << kwargs }) do
          CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
            job.perform(course_id: course.id, user_id: teacher.id)
          end
        end
      end
    end

    assert_equal 1, enqueued.size
    assert_equal true, enqueued.first[:skip_user_codex]
    assert_equal course.id, enqueued.first[:course_id]

    course.reload
    assert_not_equal "failed", course.outline_research_stage
    assert_nil course.outline_research_error
  end

  test "uses development stub pipeline and pre-fills guidance answers" do
    teacher = users(:admin)
    course = courses(:one)
    course.update!(
      outline: [ { "Topic One" => "Details" } ],
      outline_research_stage: "idle",
      outline_guidance_answers: {}
    )

    CourseOutlineResearchStubService.stub(:enabled?, true) do
      ExaApiService.stub(:new, ->(**_kwargs) { raise "Exa should not run in stub mode" }) do
        OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { raise "Responses API should not run in stub mode" }) do
          CourseOutlineResearchBroadcasts.stub(:broadcast_editor_state, true) do
            EnrichCourseOutlineJob.perform_now(
              course_id: course.id,
              user_id: teacher.id,
              source: "teacher_chat_tool"
            )
          end
        end
      end
    end

    course.reload
    assert_equal "awaiting_teacher_input", course.outline_research_stage
    assert_predicate course.outline_guidance_report_md.to_s, :present?
    assert_operator course.outline_guidance_questions.size, :>, 0
    assert_operator course.outline_guidance_answers.size, :>, 0
    assert_equal [], course.unanswered_research_question_ids
    assert_equal "completed", course.outline_research_hash.dig("exa_research", "status")
  end

  private

  def ensure_prompt(category, text)
    Prompt.find_or_create_by!(category: category, teacher_id: nil) do |prompt|
      prompt.title = category.humanize
      prompt.prompt = text
    end
  end
end
