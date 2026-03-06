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

    test "generate_content does not enqueue when generation already in progress" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "generating_content")

      assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
        post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
      end

      assert_response :success
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
        assert_includes @response.body, "A generation request was just queued."
      end
    end

    test "generate_content with propose_resources=true warns when resource proposal features are disabled" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "idle")

      AppSetting.stub(:openai_agent_enabled?, false) do
        AppSetting.stub(:exa_enabled?, false) do
          assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
            post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson),
                 params: { propose_resources: true },
                 as: :turbo_stream
          end
        end
      end

      assert_response :success
      assert_includes @response.body, "Configure OpenAI Agent Runs and Exa API before proposing resources."
    end

    test "propose_resources enqueues job when generation is completed and features are enabled" do
      sign_in(users(:admin))
      lesson = lessons(:one)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
      lesson_plan.update!(generation_stage: "completed")

      AppSetting.stub(:openai_agent_enabled?, true) do
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
