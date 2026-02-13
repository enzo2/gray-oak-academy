require "test_helper"

module Admin
  class CoursesControllerResearchTest < ActionDispatch::IntegrationTest
    test "edit shows generate outline button and hides research panel when outline is blank" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(outline: [])

      AppSetting.stub(:openai_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          get edit_admin_course_path(course)
        end
      end

      assert_response :success
      assert_includes response.body, "Generate Outline"
      assert_not_includes response.body, "Outline Research"
    end

    test "edit shows research panel only when outline exists and research features are enabled" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(outline: [ { "Topic" => "Details" } ])

      AppSetting.stub(:openai_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          get edit_admin_course_path(course)
        end
      end
      assert_response :success
      assert_includes response.body, "Outline Research"
      assert_not_includes response.body, "Generate Outline"

      AppSetting.stub(:openai_agent_enabled?, false) do
        AppSetting.stub(:exa_enabled?, true) do
          get edit_admin_course_path(course)
        end
      end
      assert_response :success
      assert_not_includes response.body, "Outline Research"
    end

    test "edit shows completion fanfare and apply summary when research is completed" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        outline: [ { "Topic" => "Details" } ],
        outline_research_stage: "completed",
        outline_guidance_report_md: "## Guidance\nUse the research framing.",
        outline_research: {
          "source_anchors" => [],
          "coverage_gaps" => [],
          "factual_notes" => [],
          "alternative_approaches" => [],
          "apply_agent_summary_md" => "Applied successfully.",
          "apply_completed_at" => "2026-02-12T16:44:06Z"
        }
      )

      AppSetting.stub(:openai_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          get edit_admin_course_path(course)
        end
      end

      assert_response :success
      assert_includes response.body, "Research Pipeline Complete"
      assert_includes response.body, "Applied successfully."
      assert_includes response.body, "View Guidance Report"
      assert_includes response.body, "Open full guidance report"
      assert_includes response.body, "Research Findings Snapshot"
      assert_not_includes response.body, "Research Outline"
    end

    test "edit hides guidance report link when report is missing" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        outline: [ { "Topic" => "Details" } ],
        outline_research_stage: "completed",
        outline_guidance_report_md: nil,
        outline_research: {
          "source_anchors" => [],
          "coverage_gaps" => [],
          "factual_notes" => [],
          "alternative_approaches" => [],
          "apply_agent_summary_md" => "Applied successfully.",
          "apply_completed_at" => "2026-02-12T16:44:06Z"
        }
      )

      AppSetting.stub(:openai_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          get edit_admin_course_path(course)
        end
      end

      assert_response :success
      assert_not_includes response.body, "View Guidance Report"
      assert_not_includes response.body, "Open full guidance report"
    end

    test "edit enables start button for failed non-resumable run" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        outline: [ { "Topic" => "Details" } ],
        outline_research_stage: "failed",
        outline_research_response_id: nil
      )

      AppSetting.stub(:openai_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          get edit_admin_course_path(course)
        end
      end

      assert_response :success
      assert_select "form[action='#{start_outline_research_admin_course_path(course)}'] button:not([disabled])", text: /Research Outline/
    end

    test "edit disables start button for failed resumable run" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        outline: [ { "Topic" => "Details" } ],
        outline_research_stage: "failed",
        outline_research_response_id: "resp_123"
      )

      AppSetting.stub(:openai_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          get edit_admin_course_path(course)
        end
      end

      assert_response :success
      assert_select "form[action='#{start_outline_research_admin_course_path(course)}'] button[disabled]", text: /Research Outline/
    end

    test "start_outline_research redirects to edit and calls async service" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)

      captured_kwargs = {}
      fake_service = Object.new
      fake_service.define_singleton_method(:enqueue_start) do
        { ok: true, stage: "researching_outline", message: "Queued outline research." }
      end

      CourseOutlineResearchAsyncService.stub(:new, ->(**kwargs) {
        captured_kwargs = kwargs
        fake_service
      }) do
        post start_outline_research_admin_course_path(course)
      end

      assert_redirected_to edit_admin_course_path(course)
      assert_equal course, captured_kwargs[:course]
      assert_equal teacher, captured_kwargs[:current_user]
      assert_equal "course_edit_page", captured_kwargs[:source]
    end

    test "outline_research_input renders awaiting-teacher-input workspace" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        outline_research_stage: "awaiting_teacher_input",
        outline_research: { "source_anchors" => [] },
        outline_guidance_questions: [ { "id" => "q1", "question" => "Question one?" } ],
        outline_guidance_answers: {}
      )

      get outline_research_input_admin_course_path(course)

      assert_response :success
      assert_includes response.body, "Outline Research Input"
      assert_includes response.body, "Source Anchors"
      assert_includes response.body, "Question Responses"
    end

    test "outline_research_input renders read-only report mode when completed and report exists" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        outline_research_stage: "completed",
        outline_guidance_report_md: "## Guidance\nUse more chronology.",
        outline_research: {
          "apply_agent_summary_md" => "Applied updates.",
          "apply_completed_at" => "2026-02-12T16:44:06Z"
        }
      )

      get outline_research_input_admin_course_path(course)

      assert_response :success
      assert_includes response.body, "Outline Research Report"
      assert_includes response.body, "Guidance Report"
      assert_includes response.body, "Applied updates."
      assert_not_includes response.body, "Resume Agent Apply Phase"
      assert_not_includes response.body, "Save Progress"
    end

    test "outline_research_input redirects when completed and report is missing" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        outline_research_stage: "completed",
        outline_guidance_report_md: nil
      )

      get outline_research_input_admin_course_path(course)

      assert_redirected_to edit_admin_course_path(course)
      follow_redirect!
      assert_includes response.body, "Outline research review is only available while awaiting teacher input, after a failed apply run, or when a guidance report exists."
    end

    test "submit_outline_research_inputs from workspace saves structured response and additional comments" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        outline_research_stage: "awaiting_teacher_input",
        outline_research: { "source_anchors" => [] },
        outline_guidance_questions: [
          { "id" => "q1", "question" => "Question one?" },
          { "id" => "q2", "question" => "Question two?" }
        ],
        outline_guidance_answers: {}
      )

      patch submit_outline_research_inputs_admin_course_path(course), params: {
        from_outline_research_input: "1",
        question_choices: { q1: "B" },
        additional_comments: "Use research guidance where useful."
      }

      assert_redirected_to outline_research_input_admin_course_path(course)
      course.reload
      answer_payload = course.outline_guidance_answers["q1"]
      assert_equal "B", answer_payload["choice"]
      assert_equal "Use research guidance where useful.", course.outline_guidance_additional_comments
    end

    test "submit_outline_research_inputs persists teacher answers and anchor decisions" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)

      course.update!(
        outline_research_stage: "awaiting_teacher_input",
        outline_research: {
          "source_anchors" => [
            { "id" => "anchor_1", "decision" => "pending" },
            { "id" => "anchor_2", "decision" => "pending" }
          ]
        },
        outline_guidance_questions: [
          { "id" => "q1", "question" => "Question one?" }
        ],
        outline_guidance_answers: {}
      )

      patch submit_outline_research_inputs_admin_course_path(course), params: {
        question_choices: { q1: "B" },
        source_anchor_decisions: { "0" => "approved", "1" => "rejected" }
      }

      assert_redirected_to edit_admin_course_path(course)
      course.reload
      answer_payload = course.outline_guidance_answers["q1"]
      assert_equal "B", answer_payload["choice"]
      assert_equal "approved", course.outline_research.dig("source_anchors", 0, "decision")
      assert_equal "rejected", course.outline_research.dig("source_anchors", 1, "decision")
    end

    test "resume_outline_research passes permission and saves latest inputs first" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)

      course.update!(
        outline_research_stage: "awaiting_teacher_input",
        outline_research: {
          "source_anchors" => [
            { "id" => "anchor_1", "decision" => "pending" }
          ]
        },
        outline_guidance_questions: [
          { "id" => "q1", "question" => "Question one?" }
        ],
        outline_guidance_answers: {}
      )

      captured_permission = nil
      fake_service = Object.new
      fake_service.define_singleton_method(:enqueue_resume) do |permission_granted:|
        captured_permission = permission_granted
        { ok: true, stage: "applying_guidance_updates", message: "Queued research-apply run." }
      end

      CourseOutlineResearchAsyncService.stub(:new, ->(**_kwargs) { fake_service }) do
        post resume_outline_research_admin_course_path(course), params: {
          from_outline_research_input: "1",
          allow_agent_modifications: "1",
          question_choices: { q1: "C" },
          source_anchor_decisions: { "0" => "approved" }
        }
      end

      assert_redirected_to edit_admin_course_path(course)
      assert_equal true, captured_permission
      course.reload
      answer_payload = course.outline_guidance_answers["q1"]
      assert_equal "C", answer_payload["choice"]
      assert_equal "approved", course.outline_research.dig("source_anchors", 0, "decision")
    end

    test "submit_outline_research_inputs redirects when not awaiting teacher input" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(outline_research_stage: "completed")

      patch submit_outline_research_inputs_admin_course_path(course), params: {
        question_choices: { q1: "A" }
      }

      assert_redirected_to edit_admin_course_path(course)
      follow_redirect!
      assert_includes response.body, "Outline research input is only available while awaiting teacher input or after a failed apply run."
    end

    test "resume_outline_research redirects when not awaiting teacher input" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(outline_research_stage: "completed")

      post resume_outline_research_admin_course_path(course), params: {
        allow_agent_modifications: "1"
      }

      assert_redirected_to edit_admin_course_path(course)
      follow_redirect!
      assert_includes response.body, "Outline research input is only available while awaiting teacher input or after a failed apply run."
    end

    test "resume_outline_research is blocked for failed non-resumable run" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        outline_research_stage: "failed",
        outline_research_response_id: nil,
        outline_research: { "source_anchors" => [] },
        outline_guidance_questions: [],
        outline_guidance_answers: {}
      )

      post resume_outline_research_admin_course_path(course), params: {
        from_outline_research_input: "1",
        allow_agent_modifications: "1"
      }

      assert_redirected_to outline_research_input_admin_course_path(course)
      follow_redirect!
      assert_includes response.body, "cannot be resumed"
    end

    test "undo_outline_research_changes delegates to undo service" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)

      fake_undo = Object.new
      fake_undo.define_singleton_method(:undo!) do
        { ok: true, message: "Reverted the latest agent-applied course changes." }
      end

      UndoCourseResearchChangesService.stub(:new, ->(**_kwargs) { fake_undo }) do
        post undo_outline_research_changes_admin_course_path(course)
      end

      assert_redirected_to edit_admin_course_path(course)
    end
  end
end
