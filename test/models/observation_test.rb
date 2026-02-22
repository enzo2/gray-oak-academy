require "test_helper"

class ObservationTest < ActiveSupport::TestCase
  test "effective_weight uses created_at when never validated" do
    travel_to Time.zone.parse("2026-01-01 12:00:00 UTC") do
      observation = Observation.create!(
        student: users(:student),
        content: "Half-life test",
        status: :approved,
        relevance_weight: 1.0,
        created_at: 90.days.ago
      )

      assert_in_delta 0.5, observation.effective_weight, 0.02
    end
  end

  test "effective_weight uses last_validated_at when present" do
    travel_to Time.zone.parse("2026-01-01 12:00:00 UTC") do
      observation = Observation.create!(
        student: users(:student),
        content: "Recently validated",
        status: :approved,
        relevance_weight: 0.8,
        created_at: 2.years.ago,
        last_validated_at: 10.days.ago
      )

      expected = 0.8 * (0.5 ** (10.0 / Observation::HALF_LIFE_DAYS))
      assert_in_delta expected, observation.effective_weight, 0.01
    end
  end

  test "effective_weight decays to quarter weight after two half lives" do
    travel_to Time.zone.parse("2026-01-01 12:00:00 UTC") do
      observation = Observation.create!(
        student: users(:student),
        content: "Quarter-life test",
        status: :approved,
        relevance_weight: 1.0,
        created_at: 180.days.ago
      )

      assert_in_delta 0.25, observation.effective_weight, 0.02
    end
  end

  test "for_context returns only approved observations" do
    student = users(:student)
    approved = Observation.create!(student: student, content: "Approved", status: :approved, relevance_weight: 1.0)
    Observation.create!(student: student, content: "Pending", status: :pending, relevance_weight: 1.0)
    Observation.create!(student: student, content: "Rejected", status: :rejected, relevance_weight: 1.0)

    results = student.observations.for_context

    assert_includes results, approved
    refute results.any?(&:status_pending?)
    refute results.any?(&:status_rejected?)
  end

  test "for_context orders by decayed effective weight" do
    travel_to Time.zone.parse("2026-01-01 12:00:00 UTC") do
      student = users(:student)
      older_high = Observation.create!(
        student: student,
        content: "Older but more relevant",
        status: :approved,
        relevance_weight: 1.0,
        created_at: 30.days.ago,
        last_validated_at: 20.days.ago
      )
      newer_low = Observation.create!(
        student: student,
        content: "Newer but low base weight",
        status: :approved,
        relevance_weight: 0.2,
        created_at: 1.day.ago
      )

      results = student.observations.for_context.limit(2).to_a

      assert_equal [ older_high.id, newer_low.id ], results.map(&:id)
      assert results.first.has_attribute?("effective_weight")
      assert_operator results.first.effective_weight, :>, results.second.effective_weight
    end
  end
end
