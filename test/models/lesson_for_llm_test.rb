require "test_helper"

class LessonForLlmTest < ActiveSupport::TestCase
  setup do
    @lesson = lessons(:one)
  end

  test "for_llm returns lesson and lesson_plan shape" do
    payload = ActiveSupport::HashWithIndifferentAccess.new(@lesson.for_llm)

    # Ensure top-level keys
    assert payload.key?("lesson"), "expected lesson key"
    lesson_section = payload["lesson"].with_indifferent_access
    assert_equal @lesson.id, lesson_section["id"]
    assert_equal @lesson.title, lesson_section["title"]
    assert lesson_section.key?("goals")
    assert lesson_section.key?("approx_duration_min")

    # lesson_plan may be present in fixtures; when present it should include linked_resources as JSON/string
    lp_section = payload["lesson_plan"]
    if lp_section
      lp = lp_section.with_indifferent_access
      assert lp.key?("id")
      assert lp.key?("status")
      assert lp.key?("content")
      assert lp.key?("linked_resources")
      # linked_resources is produced with pretty: false which returns a JSON string
      linked = lp["linked_resources"]
      assert linked.is_a?(String)
      parsed = JSON.parse(linked) rescue nil
      assert parsed.is_a?(Array), "linked_resources should parse to an array"
    end
  end
end
