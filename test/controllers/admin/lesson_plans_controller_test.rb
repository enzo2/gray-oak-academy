require "test_helper"

module Admin
  class LessonPlansControllerTest < ActionDispatch::IntegrationTest
    test "edit action renders successfully for lesson without lesson plan" do
      teacher = users(:admin) # Assuming 'admin' is a teacher
      sign_in(teacher)

      # Create a fresh lesson without a lesson plan
      course = courses(:one)
      lesson = Lesson.create!(
        title: "New Lesson No Plan",
        goals: "Testing goals",
        approx_duration_min: 30,
        course: course,
        position: 100
      )

      # Ensure no lesson plan exists
      assert_nil lesson.lesson_plan

      # Visit the edit page (which triggers set_lesson_plan and build_lesson_plan)
      get edit_admin_course_lesson_lesson_plan_path(course, lesson)

      assert_response :success
      # Verify that a new lesson plan was initialized but not necessarily persisted yet
      # (The controller only builds it, it doesn't save it in 'edit')
    end

    test "edit renders revise controls for existing lesson plan content" do
      teacher = users(:admin)
      sign_in(teacher)
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan
      lesson_plan.update!(content: [ { "Knowledge" => "Existing explanation." } ])

      get edit_admin_course_lesson_lesson_plan_path(lesson.course, lesson)

      assert_response :success
      assert_select "#generate-lesson-plan-button", text: /Revise with LLM/
      assert_select "label", text: /Revision instruction/
      assert_includes @response.body, "Shorten / Condense"
      assert_includes @response.body, "Your current outline edits are included automatically."
      assert_select "[data-lesson-plan-steering-target='contentSnapshot']"
      assert_select "form[data-action*='submit->lesson-plan-steering#snapshotContent']"
      assert_select "form[data-action*='formdata->lesson-plan-steering#appendContentSnapshot']"
      assert_select "button[type='submit'][data-action*='click->lesson-plan-steering#snapshotContent']", count: 0
    end

    test "generate_content persists submitted outline before revising" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "idle", content: [ { "Knowledge" => "Old details." } ])

      assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob do
        post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson),
             params: {
               preset: "other",
               guidance: "Add a hands-on activity.",
               lesson_plan: {
                 content_keys: [ "Knowledge", "Activity" ],
                 content_values: [ "Edited details.", "New hands-on activity." ]
               }
             },
             as: :turbo_stream
      end

      assert_response :success
      assert_equal "true", response.headers["X-Lesson-Plan-Generation-Queued"]
      assert_equal(
        [ { "Knowledge" => "Edited details." }, { "Activity" => "New hands-on activity." } ],
        lesson_plan.reload.content
      )
    end

    test "generate_content rejects an empty submitted outline before revising" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      original_content = [ { "Knowledge" => "Keep this saved content." } ]
      lesson_plan.update!(generation_stage: "idle", content: original_content)

      assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
        post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson),
             params: {
               preset: "condense",
               lesson_plan: { content_snapshot: "1" }
             },
             as: :turbo_stream
      end

      assert_response :success
      assert_equal "false", response.headers["X-Lesson-Plan-Generation-Queued"]
      assert_equal original_content, lesson_plan.reload.content
      assert_includes @response.body, "The current outline is empty, so revision was not started"
    end

    test "generate_content accepts the condense revise preset" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "idle", content: [ { "Knowledge" => "Long explanation." } ])

      assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob do
        post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson),
             params: { preset: "condense" },
             as: :turbo_stream
      end

      assert_response :success
      assert_equal "true", response.headers["X-Lesson-Plan-Generation-Queued"]
    end

    test "edit renders propose resources button while suggested resources remain" do
      teacher = users(:admin)
      sign_in(teacher)
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan
      lesson_plan.update!(
        content: [ { "Knowledge" => "Existing explanation." } ],
        suggested_resources: [ { "Video" => "Equivalent fractions visual walkthrough." } ],
        generation_stage: "completed"
      )

      AppSetting.stub(:background_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          get edit_admin_course_lesson_lesson_plan_path(lesson.course, lesson)
        end
      end

      assert_response :success
      assert_select "#resource-proposal-controls button", text: /Propose Resources/
      assert_includes @response.body, "Use Propose Resources below to locate and link web-available items when ready."
    end

    test "edit renders collapsed sources-consulted block when generation research is present" do
      teacher = users(:admin)
      sign_in(teacher)
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan
      lesson_plan.update!(
        content: [ { "Knowledge" => "Existing explanation." } ],
        generation_metadata: {
          "searches" => [ "current fractions standards" ],
          "sources" => [ { "url" => "https://example.com/a", "title" => "Source A" } ]
        }
      )

      get edit_admin_course_lesson_lesson_plan_path(lesson.course, lesson)

      assert_response :success
      # Collapsed by default: a <details> without the open attribute.
      assert_select "details:not([open]) > summary", text: /Sources consulted during generation/
      assert_select "details a[href='https://example.com/a']", text: "Source A"
      assert_includes @response.body, "current fractions standards"
    end

    test "quick lesson plan editor links back to quick lessons" do
      teacher = users(:admin)
      sign_in(teacher)
      quick_lesson = teacher.taught_courses.create!(
        kind: "quick_lesson",
        title: "Quick Fractions",
        summary: "Understand common denominators using shared units.",
        grade_level: "5"
      )
      lesson = quick_lesson.lessons.create!(
        title: "Quick Fractions",
        goals: "Understand common denominators using shared units.",
        approx_duration_min: 20
      )

      get edit_admin_course_lesson_lesson_plan_path(quick_lesson, lesson)

      assert_response :success
      assert_select "a[href='#{admin_quick_lessons_path}']", text: "Back to Quick Lessons"
      assert_select "a[href='#{admin_quick_lessons_path}']", text: "Cancel"
      assert_select "a", text: "Back to Lessons", count: 0
    end

    test "destroying a quick lesson plan redirects to quick lessons" do
      teacher = users(:admin)
      sign_in(teacher)
      quick_lesson = teacher.taught_courses.create!(
        kind: "quick_lesson",
        title: "Quick Fractions",
        summary: "Understand common denominators using shared units.",
        grade_level: "5"
      )
      lesson = quick_lesson.lessons.create!(
        title: "Quick Fractions",
        goals: "Understand common denominators using shared units.",
        approx_duration_min: 20
      )
      lesson_plan = lesson.create_lesson_plan!(status: "draft", content: [ { "Warmup" => "Intro review." } ])

      assert_difference("LessonPlan.count", -1) do
        delete admin_course_lesson_lesson_plan_path(quick_lesson, lesson)
      end

      assert_not LessonPlan.exists?(lesson_plan.id)
      assert_redirected_to admin_quick_lessons_path
    end

    test "unlink pending linked resource deletes resource" do
      teacher = users(:admin)
      sign_in(teacher)
      lesson = lessons(:one)
      lesson_plan = lesson_plans(:one)
      pending_resource = Resource.create!(
        teacher: teacher,
        category: "Article",
        description: "Pending resource",
        uri: "https://example.com/pending-resource",
        approved: false
      )
      lesson_plan.resources << pending_resource

      assert_difference("Resource.count", -1) do
        delete unlink_resource_admin_course_lesson_lesson_plan_path(lesson.course, lesson, resource_id: pending_resource.id), as: :turbo_stream
      end

      assert_response :success
      assert_not lesson_plan.reload.resources.exists?(id: pending_resource.id)
    end

    test "link_resource persists a newly built lesson plan before linking" do
      teacher = users(:admin)
      sign_in(teacher)

      course = courses(:one)
      lesson = Lesson.create!(
        title: "Resource Link Test Lesson",
        goals: "This lesson verifies resource linking persists.",
        approx_duration_min: 30,
        course: course,
        position: 101
      )
      resource = resources(:one)

      assert_nil lesson.lesson_plan
      post link_resource_admin_course_lesson_lesson_plan_path(course, lesson, resource_id: resource.id), as: :turbo_stream

      assert_response :success
      assert lesson.reload.lesson_plan.present?
      assert lesson.lesson_plan.resources.exists?(id: resource.id)
    end

    test "unlink approved linked resource only unlinks it" do
      teacher = users(:admin)
      sign_in(teacher)
      lesson = lessons(:one)
      lesson_plan = lesson_plans(:one)
      approved_resource = Resource.create!(
        teacher: teacher,
        category: "Article",
        description: "Approved resource",
        uri: "https://example.com/approved-resource",
        approved: true
      )
      lesson_plan.resources << approved_resource

      assert_no_difference("Resource.count") do
        delete unlink_resource_admin_course_lesson_lesson_plan_path(lesson.course, lesson, resource_id: approved_resource.id), as: :turbo_stream
      end

      assert_response :success
      assert_not lesson_plan.reload.resources.exists?(id: approved_resource.id)
      assert Resource.exists?(approved_resource.id)
    end

    test "delete_resource removes linked resource record" do
      teacher = users(:admin)
      sign_in(teacher)
      lesson = lessons(:one)
      lesson_plan = lesson_plans(:one)
      resource = Resource.create!(
        teacher: teacher,
        category: "Article",
        description: "Delete me",
        uri: "https://example.com/delete-resource",
        approved: false
      )
      lesson_plan.resources << resource

      assert_difference("Resource.count", -1) do
        delete delete_resource_admin_course_lesson_lesson_plan_path(lesson.course, lesson, resource_id: resource.id), as: :turbo_stream
      end

      assert_response :success
      assert_not lesson_plan.reload.resources.exists?(id: resource.id)
    end

    test "cannot link another teacher resource" do
      teacher = users(:admin)
      sign_in(teacher)

      lesson = lessons(:one)
      other_teacher_resource = resources(:two)

      post link_resource_admin_course_lesson_lesson_plan_path(lesson.course, lesson, resource_id: other_teacher_resource.id), as: :turbo_stream

      assert_response :not_found
      assert_not lesson.lesson_plan.resources.exists?(id: other_teacher_resource.id)
    end

    test "cannot link pending resource while lesson plan is published" do
      teacher = users(:admin)
      sign_in(teacher)

      lesson = lessons(:one)
      lesson_plan = lesson_plans(:one)
      lesson_plan.update!(content: [ { "Intro" => "Ready" } ], status: "published")
      pending_resource = Resource.create!(
        teacher: teacher,
        category: "Article",
        description: "Pending resource",
        uri: "https://example.com/pending-link",
        approved: false
      )

      assert_no_difference("lesson_plan.reload.resources.count") do
        post link_resource_admin_course_lesson_lesson_plan_path(lesson.course, lesson, resource_id: pending_resource.id), as: :turbo_stream
      end

      assert_response :success
      assert_not lesson_plan.reload.resources.exists?(id: pending_resource.id)
      assert_includes @response.body, "The lesson plan is published. If you want to link a pending resource, please change the lesson plan back to draft status."
    end

    test "cannot delete another teacher pending linked resource" do
      teacher = users(:admin)
      sign_in(teacher)
      lesson = lessons(:one)
      lesson_plan = lesson_plans(:one)
      other_teacher_pending_resource = Resource.create!(
        teacher: users(:admin2),
        category: "Article",
        description: "Other teacher pending resource",
        uri: "https://example.com/other-teacher-pending-resource",
        approved: false
      )
      lesson_plan.resources << other_teacher_pending_resource

      assert_no_difference("Resource.count") do
        delete delete_resource_admin_course_lesson_lesson_plan_path(lesson.course, lesson, resource_id: other_teacher_pending_resource.id), as: :turbo_stream
      end

      assert_response :not_found
      assert lesson_plan.reload.resources.exists?(id: other_teacher_pending_resource.id)
      assert Resource.exists?(other_teacher_pending_resource.id)
    end

    test "cannot unlink another teacher pending linked resource" do
      teacher = users(:admin)
      sign_in(teacher)
      lesson = lessons(:one)
      lesson_plan = lesson_plans(:one)
      other_teacher_pending_resource = Resource.create!(
        teacher: users(:admin2),
        category: "Article",
        description: "Other teacher pending resource",
        uri: "https://example.com/other-teacher-pending-resource",
        approved: false
      )
      lesson_plan.resources << other_teacher_pending_resource

      assert_no_difference("Resource.count") do
        delete unlink_resource_admin_course_lesson_lesson_plan_path(lesson.course, lesson, resource_id: other_teacher_pending_resource.id), as: :turbo_stream
      end

      assert_response :not_found
      assert lesson_plan.reload.resources.exists?(id: other_teacher_pending_resource.id)
      assert Resource.exists?(other_teacher_pending_resource.id)
    end

    test "cannot generate content for another teacher lesson" do
      sign_in(users(:admin2))
      lesson = lessons(:one)

      assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
        post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
      end

      assert_response :not_found
    end

    test "cannot edit another teacher lesson plan" do
      sign_in(users(:admin))
      lesson = lessons(:two)

      get edit_admin_course_lesson_lesson_plan_path(lesson.course, lesson)

      assert_response :not_found
    end

    test "generate_content marks queued responses in header" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "idle")

      assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob do
        post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
      end

      assert_response :success
      assert_equal "true", response.headers["X-Lesson-Plan-Generation-Queued"]
    end

    test "generate_content does not enqueue when generation already in progress" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "generating_content")

      assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
        post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
      end

      assert_response :success
      assert_equal "false", response.headers["X-Lesson-Plan-Generation-Queued"]
      assert_includes @response.body, "Generation is already in progress for this lesson plan."
    end

    test "generate_content applies cooldown to prevent immediate retrigger" do
      cache = ActiveSupport::Cache::MemoryStore.new
      Rails.stub(:cache, cache) do
        sign_in(users(:admin))
        lesson = lessons(:one)
        lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
        lesson_plan.update!(generation_stage: "idle")

        assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob do
          post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
        end

        # Simulate the stage moving out of in-progress quickly; cooldown should still block requeue.
        lesson_plan.reload.update!(generation_stage: "completed")

        assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
          post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
        end

        assert_response :success
        assert_equal "false", response.headers["X-Lesson-Plan-Generation-Queued"]
        assert_includes @response.body, "A generation request was just queued."
      end
    end

    test "generate_content with propose_resources=true warns when resource proposal features are disabled" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "idle")

      AppSetting.stub(:background_agent_enabled?, false) do
        AppSetting.stub(:exa_enabled?, false) do
          assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
            post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson),
                 params: { propose_resources: true },
                 as: :turbo_stream
          end
        end
      end

      assert_response :success
      assert_equal "false", response.headers["X-Lesson-Plan-Generation-Queued"]
      assert_includes @response.body, "Configure Background Agent Runs and Exa API before proposing resources."
    end

    test "generate_content requires custom guidance when preset is other" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "idle")

      assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
        post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson),
             params: { preset: "other", guidance: "" },
             as: :turbo_stream
      end

      assert_response :success
      assert_equal "false", response.headers["X-Lesson-Plan-Generation-Queued"]
      assert_includes @response.body, "Enter lesson plan guidance when using the Other preset."
    end

    test "generate_content with blank other guidance does not persist a new lesson plan" do
      sign_in(users(:admin))
      course = courses(:one)
      lesson = Lesson.create!(
        title: "Guidance Validation Lesson",
        goals: "Verify failed steering validation does not persist a lesson plan.",
        approx_duration_min: 30,
        course: course,
        position: 102
      )

      assert_nil lesson.lesson_plan

      assert_no_difference("LessonPlan.count") do
        assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
          post generate_content_admin_course_lesson_lesson_plan_path(course, lesson),
               params: { preset: "other", guidance: "" },
               as: :turbo_stream
        end
      end

      assert_response :success
      assert_equal "false", response.headers["X-Lesson-Plan-Generation-Queued"]
      assert_nil lesson.reload.lesson_plan
      assert_includes @response.body, "Enter lesson plan guidance when using the Other preset."
    end

    test "propose_resources enqueues job when generation is completed and features are enabled" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "completed")

      AppSetting.stub(:background_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          assert_enqueued_jobs 1, only: ProposeResourcesJob do
            post propose_resources_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
          end
        end
      end

      assert_response :success
      assert_equal "proposing_resources", lesson_plan.reload.generation_stage
    end

    test "cannot propose resources for another teacher lesson" do
      sign_in(users(:admin2))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "completed")

      assert_enqueued_jobs 0, only: ProposeResourcesJob do
        post propose_resources_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
      end

      assert_response :not_found
    end
  end
end
