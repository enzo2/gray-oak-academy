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

    test "update rejects edits while outline research is in progress" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(
        title: "Locked Course",
        summary: "Original summary that should remain unchanged while the editor is locked.",
        grade_level: "5",
        outline: [ { "Topic" => "Details" } ],
        outline_research_stage: "researching_outline"
      )

      patch admin_course_path(course), params: {
        course: {
          title: "Changed Title",
          summary: "Updated summary that should not be persisted because the lock is active.",
          grade_level: "6",
          outline_topics: [ "Updated Topic" ],
          outline_details: [ "Updated Details" ]
        }
      }

      assert_redirected_to edit_admin_course_path(course)
      assert_equal "Course edits are locked while outline research is in progress.", flash[:alert]

      course.reload
      assert_equal "Locked Course", course.title
      assert_equal "Original summary that should remain unchanged while the editor is locked.", course.summary
      assert_equal "5", course.grade_level
      assert_equal [ { "Topic" => "Details" } ], course.outline
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

    test "index hides quick lessons from course manager" do
      teacher = users(:admin)
      sign_in(teacher)
      Course.create!(
        teacher: teacher,
        kind: "quick_lesson",
        title: "Quick Fractions",
        summary: "A quick one-off lesson about common denominators.",
        grade_level: "5"
      )

      get admin_courses_path

      assert_response :success
      assert_not_includes response.body, "Quick Fractions"
    end

    test "course routes do not expose quick lessons by direct url" do
      teacher = users(:admin)
      sign_in(teacher)
      quick_lesson = Course.create!(
        teacher: teacher,
        kind: "quick_lesson",
        title: "Quick Fractions",
        summary: "A quick one-off lesson about common denominators.",
        grade_level: "5"
      )

      get edit_admin_course_path(quick_lesson)

      assert_response :not_found
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
