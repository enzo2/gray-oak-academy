require "application_system_test_case"
require "timeout"

class OutlineFormAutosizeTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
  end

  test "course outline textarea falls back to js autosize when field sizing is unsupported" do
    course = Course.create!(
      title: "Autosize Course",
      summary: "Used to verify outline textarea resizing fallback.",
      outline: [ { "Topic 1" => "One line" } ],
      grade_level: "4",
      teacher: @admin
    )

    sign_in @admin
    visit edit_admin_course_path(course)

    assert_autosize_fallback("textarea[name='course[outline_details][]']")
  end

  test "lesson plan textarea falls back to js autosize when field sizing is unsupported" do
    lesson = lessons(:one)

    sign_in @admin
    visit edit_admin_course_lesson_lesson_plan_path(lesson.course, lesson)

    assert_autosize_fallback("textarea[name='lesson_plan[content_values][]']")
  end

  private

  def assert_autosize_fallback(selector)
    textarea = find(selector, match: :first, visible: :all)

    page.execute_script(<<~JS, textarea.native)
      window.__originalCssSupports = window.CSS?.supports?.bind(window.CSS);

      if (window.CSS) {
        window.CSS.supports = function(property, value) {
          if (property === "field-sizing" && value === "content") return false;
          return window.__originalCssSupports ? window.__originalCssSupports(property, value) : false;
        };
      }

      const textarea = arguments[0];
      textarea.value = "Line 1\\nLine 2\\nLine 3\\nLine 4";
      document.dispatchEvent(new Event("turbo:render"));
    JS

    assert_eventually do
      textarea.evaluate_script("this.style.height").match?(/\A\d+px\z/)
    end

    height = textarea.evaluate_script("this.style.height")

    assert_match(/\A\d+px\z/, height)
    assert_operator height.delete_suffix("px").to_i, :>, 20
  ensure
    page.execute_script(<<~JS)
      if (window.CSS && window.__originalCssSupports) {
        window.CSS.supports = window.__originalCssSupports;
      }

      delete window.__originalCssSupports;
    JS
  end

  def assert_eventually(timeout: Capybara.default_max_wait_time)
    Timeout.timeout(timeout) do
      loop do
        return if yield

        sleep 0.05
      end
    end
  end
end
