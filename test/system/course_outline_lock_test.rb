require "application_system_test_case"

class CourseOutlineLockTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
  end

  test "course save is disabled while outline research locks the outline" do
    course = Course.create!(
      title: "Locked Outline Course",
      summary: "Used to verify the course editor cannot submit while locked.",
      outline: [ { "Topic 1" => "Details" } ],
      grade_level: "4",
      teacher: @admin,
      outline_research_stage: "researching_outline"
    )

    sign_in @admin
    visit edit_admin_course_path(course)

    assert_selector "#form_course_#{course.id} input[type='submit'][disabled]", wait: 5
    assert_field "Title", disabled: true
  end

  test "outline research start is blocked while the course form has unsaved changes" do
    course = Course.create!(
      title: "Dirty Outline Course",
      summary: "Used to verify research start waits for saved course edits.",
      outline: [ { "Topic 1" => "Details" } ],
      grade_level: "4",
      teacher: @admin
    )

    AppSetting.stub(:openai_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        sign_in @admin
        visit edit_admin_course_path(course)

        fill_in "Title", with: "Unsaved Title Change"

        accept_alert("Save or discard your course edits before starting outline research.") do
          click_button "Research Outline"
        end

        assert_field "Title", with: "Unsaved Title Change"
        assert_text "Status: Idle"
      end
    end
  end
end
