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
  end
end
