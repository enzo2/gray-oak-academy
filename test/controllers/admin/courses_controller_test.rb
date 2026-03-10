require "test_helper"

module Admin
  class CoursesControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    setup do
      ActiveJob::Base.queue_adapter = :test
      clear_enqueued_jobs
    end

    test "create then generate_outline enqueues GenerateCourseOutlineJob" do
      teacher = users(:admin)
      sign_in(teacher)

      post admin_courses_path,
           params: { course: { title: "Test Course", summary: "Test course summary", grade_level: "9" } },
           as: :turbo_stream
      assert_response :success

      course = Course.order(created_at: :desc).first
      assert_equal "Test Course", course.title

      assert_enqueued_jobs 1, only: GenerateCourseOutlineJob do
        post generate_outline_admin_course_path(course), as: :turbo_stream
      end
      assert_response :success
    end

    test "teacher cannot edit another teacher course" do
      sign_in(users(:admin))

      get edit_admin_course_path(courses(:two))

      assert_response :not_found
    end

    test "index shows drafted outline status before lessons are generated" do
      teacher = users(:admin)
      sign_in(teacher)

      Course.create!(
        teacher: teacher,
        title: "Drafted Outline Course",
        summary: "A course with an outline drafted but research not yet started.",
        grade_level: "6",
        outline: [ { "Origins" => "Begin with the earliest foundations." } ],
        outline_research_stage: "idle"
      )

      AppSetting.stub(:openai_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          get admin_courses_path
        end
      end

      assert_response :success
      assert_includes response.body, "Outline drafted; not researched"
    end

    test "index falls back to no lessons added when outline research is unavailable" do
      teacher = users(:admin)
      sign_in(teacher)

      Course.create!(
        teacher: teacher,
        title: "Outline Without Research",
        summary: "A course with an outline where research cannot run in this environment.",
        grade_level: "6",
        outline: [ { "Origins" => "Begin with the earliest foundations." } ],
        outline_research_stage: "idle"
      )

      AppSetting.stub(:openai_agent_enabled?, false) do
        AppSetting.stub(:exa_enabled?, false) do
          get admin_courses_path
        end
      end

      assert_response :success
      assert_includes response.body, "No lessons added"
      assert_not_includes response.body, "Outline drafted; not researched"
    end
  end
end
