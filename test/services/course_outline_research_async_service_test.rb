require "test_helper"

class CourseOutlineResearchAsyncServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @teacher = users(:admin)
    @course = courses(:one)
    @course.update!(
      outline: [ { "Topic 1" => "Details" } ],
      outline_research_stage: "idle",
      outline_research_error: nil,
      outline_research: {},
      outline_guidance_report_md: nil,
      outline_guidance_questions: [],
      outline_guidance_answers: {},
      outline_research_run_id: nil,
      outline_research_response_id: nil
    )
  end

  test "enqueue_start queues enrich job and resets research artifacts" do
    @course.update!(course_prior_state: { "summary" => "stale snapshot" })
    conversation = conversations(:teacher_generic_conversation)

    service = CourseOutlineResearchAsyncService.new(
      course: @course,
      current_user: @teacher,
      source: "course_edit_page",
      conversation_id: conversation.id
    )

    AppSetting.stub(:background_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        emitted_events = []
        service.stub(:emit_analytics_event, ->(event_class, **_kwargs) { emitted_events << event_class }) do
          assert_enqueued_jobs 1, only: EnrichCourseOutlineJob do
            result = service.enqueue_start
            assert_equal true, result[:ok]
            assert_equal "researching_outline", result[:stage]
          end
        end
        assert_includes emitted_events, Events::CourseOutlineResearchStarted
      end
    end

    job = enqueued_jobs.find { |entry| entry[:job] == EnrichCourseOutlineJob }
    job_args = job[:args].first
    assert_equal conversation.id, job_args["conversation_id"] || job_args[:conversation_id]

    @course.reload
    assert_equal "researching_outline", @course.outline_research_stage
    assert_equal [ Course::OUTLINE_RESEARCH_PROGRESS_KEY ], @course.outline_research.keys
    assert_equal "Queued outline research...", @course.outline_research_progress["message"]
    assert_equal 1, @course.outline_research_progress["step"]
    assert_equal 4, @course.outline_research_progress["total_steps"]
    assert_equal [], @course.outline_guidance_questions
    assert_equal({}, @course.outline_guidance_answers)
    assert_nil @course.outline_guidance_report_md
    assert_nil @course.outline_research_run_id
    assert_nil @course.outline_research_response_id
    assert_equal({}, @course.course_prior_state)
  end

  test "enqueue_resume queues resume job when prerequisites are satisfied" do
    @course.update!(
      outline_research_stage: "awaiting_teacher_input",
      outline_research_response_id: "resp_123",
      outline_research: {
        "source_anchors" => [
          { "id" => "anchor_1" }
        ]
      },
      outline_guidance_questions: [
        { "id" => "q1", "question" => "Keep the current scope?" }
      ],
      outline_guidance_answers: {
        "q1" => { "choice" => "C" }
      }
    )

    service = CourseOutlineResearchAsyncService.new(
      course: @course,
      current_user: @teacher,
      source: "course_edit_page"
    )

    AppSetting.stub(:background_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        emitted_events = []
        service.stub(:emit_analytics_event, ->(event_class, **_kwargs) { emitted_events << event_class }) do
          assert_enqueued_jobs 1, only: ResumeCourseOutlineResearchJob do
            result = service.enqueue_resume(permission_granted: true)
            assert_equal true, result[:ok]
            assert_equal "applying_guidance_updates", result[:stage]
          end
        end
        assert_includes emitted_events, Events::CourseOutlineResearchResumeQueued
      end
    end

    assert_equal "applying_guidance_updates", @course.reload.outline_research_stage
  end

  test "enqueue_resume is blocked when questions are unanswered" do
    @course.update!(
      outline_research_stage: "awaiting_teacher_input",
      outline_research_response_id: "resp_123",
      outline_research: {
        "source_anchors" => [
          { "id" => "anchor_1" }
        ]
      },
      outline_guidance_questions: [
        { "id" => "q1", "question" => "Keep scope?" }
      ],
      outline_guidance_answers: {}
    )

    service = CourseOutlineResearchAsyncService.new(
      course: @course,
      current_user: @teacher,
      source: "course_edit_page"
    )

    AppSetting.stub(:background_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_enqueued_jobs 0, only: ResumeCourseOutlineResearchJob do
          result = service.enqueue_resume(permission_granted: true)
          assert_equal false, result[:ok]
          assert_includes result[:message], "must be answered"
        end
      end
    end
  end

  test "enqueue_resume allows retry when stage is failed and prerequisites are met" do
    @course.update!(
      outline_research_stage: "failed",
      outline_research_response_id: "resp_123",
      outline_research: {
        "source_anchors" => [
          { "id" => "anchor_1" }
        ]
      },
      outline_guidance_questions: [
        { "id" => "q1", "question" => "Keep the current scope?" }
      ],
      outline_guidance_answers: {
        "q1" => { "choice" => "A" }
      }
    )

    service = CourseOutlineResearchAsyncService.new(
      course: @course,
      current_user: @teacher,
      source: "course_edit_page"
    )

    AppSetting.stub(:background_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_enqueued_jobs 1, only: ResumeCourseOutlineResearchJob do
          result = service.enqueue_resume(permission_granted: true)
          assert_equal true, result[:ok]
          assert_equal "applying_guidance_updates", result[:stage]
        end
      end
    end
  end

  test "enqueue_resume is blocked when no response id exists for failed run" do
    @course.update!(
      outline_research_stage: "failed",
      outline_research_response_id: nil,
      outline_research: {
        "source_anchors" => [
          { "id" => "anchor_1" }
        ]
      },
      outline_guidance_questions: [],
      outline_guidance_answers: {}
    )

    service = CourseOutlineResearchAsyncService.new(
      course: @course,
      current_user: @teacher,
      source: "course_edit_page"
    )

    AppSetting.stub(:background_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_enqueued_jobs 0, only: ResumeCourseOutlineResearchJob do
          result = service.enqueue_resume(permission_granted: true)
          assert_equal false, result[:ok]
          assert_includes result[:message], "cannot be resumed"
        end
      end
    end
  end

  test "enqueue_start is blocked while review workflow is open" do
    @course.update!(outline_research_stage: "awaiting_teacher_input")

    service = CourseOutlineResearchAsyncService.new(
      course: @course,
      current_user: @teacher,
      source: "course_edit_page"
    )

    AppSetting.stub(:background_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_enqueued_jobs 0, only: EnrichCourseOutlineJob do
          result = service.enqueue_start
          assert_equal false, result[:ok]
          assert_includes result[:message], "review is currently open"
        end
      end
    end
  end

  test "enqueue_start allows restart from failed state without resumable response id" do
    @course.update!(
      outline_research_stage: "failed",
      outline_research_error: "Exa timed out",
      outline_research_response_id: nil
    )

    service = CourseOutlineResearchAsyncService.new(
      course: @course,
      current_user: @teacher,
      source: "course_edit_page"
    )

    AppSetting.stub(:background_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_enqueued_jobs 1, only: EnrichCourseOutlineJob do
          result = service.enqueue_start
          assert_equal true, result[:ok]
          assert_equal "researching_outline", result[:stage]
        end
      end
    end
  end

  test "enqueue_start remains blocked for failed state with resumable response id" do
    @course.update!(
      outline_research_stage: "failed",
      outline_research_response_id: "resp_123"
    )

    service = CourseOutlineResearchAsyncService.new(
      course: @course,
      current_user: @teacher,
      source: "course_edit_page"
    )

    AppSetting.stub(:background_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_enqueued_jobs 0, only: EnrichCourseOutlineJob do
          result = service.enqueue_start
          assert_equal false, result[:ok]
          assert_includes result[:message], "review is currently open"
        end
      end
    end
  end
end
