require "test_helper"

class Admin::ObservationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @teacher = users(:admin)
    @other_teacher = users(:admin2)
    @student = users(:student)
    sign_in @teacher
  end

  test "create turbo stream updates timeline and observations dashboard" do
    assert_difference("Observation.count", 1) do
      post admin_observations_path,
        params: {
          observation: {
            student_id: @student.id,
            content: "Needs explicit vocabulary scaffolding before independent writing tasks."
          },
          observation_sort: "weight_asc"
        },
        as: :turbo_stream
    end

    created_observation = Observation.order(:id).last

    assert_response :success
    assert_includes @response.body, %(target="journal_entries")
    assert_includes @response.body, %(target="journal_observations")
    assert_includes @response.body, %(id="obs_mgmt_observation_#{created_observation.id}_card_container")
    assert_match(/name="observation_sort"[^>]*value="weight_asc"/, @response.body)
  end

  test "revalidate resets last_validated_at for approved observation" do
    observation = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Needs occasional review",
      status: :approved,
      relevance_weight: 1.0,
      last_validated_at: 1.year.ago
    )
    previous_validated_at = observation.last_validated_at

    travel_to Time.zone.parse("2026-02-22 12:00:00 UTC") do
      patch revalidate_admin_observation_path(observation)
      assert_redirected_to admin_student_path(@student, active_tab: :journal_timeline)

      observation.reload
      assert_in_delta Time.current.to_f, observation.last_validated_at.to_f, 1.0
      assert_operator observation.last_validated_at, :>, previous_validated_at
    end
  end

  test "revalidate turbo stream includes flash message" do
    observation = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Turbo revalidate",
      status: :approved,
      relevance_weight: 1.0,
      last_validated_at: 1.month.ago
    )

    patch revalidate_admin_observation_path(observation), as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "flash_bar"
    assert_includes @response.body, "Observation re-validated."
    assert_includes @response.body, %(target="observation_#{observation.id}_card")
    assert_includes @response.body, %(target="obs_mgmt_observation_#{observation.id}_card_container")
  end

  test "revalidate returns forbidden for another teachers student" do
    other_student = users(:student2)
    other_student.update!(teacher: @other_teacher)

    observation = Observation.create!(
      student: other_student,
      author: @other_teacher,
      content: "Private observation",
      status: :approved,
      relevance_weight: 1.0,
      last_validated_at: 6.months.ago
    )
    original_validated_at = observation.last_validated_at

    patch revalidate_admin_observation_path(observation)

    assert_response :forbidden
    assert_equal original_validated_at.to_i, observation.reload.last_validated_at.to_i
  end

  test "revalidate rejects non-approved observations" do
    observation = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Pending review",
      status: :pending,
      relevance_weight: 1.0,
      last_validated_at: 6.months.ago
    )
    original_validated_at = observation.last_validated_at

    patch revalidate_admin_observation_path(observation)

    assert_redirected_to admin_student_path(@student, active_tab: :journal_timeline)
    assert_equal "Only approved observations can be re-validated.", flash[:alert]
    assert_equal original_validated_at.to_i, observation.reload.last_validated_at.to_i
  end

  test "show displays re-validate button for approved observation only" do
    approved_observation = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Approved item",
      status: :approved,
      relevance_weight: 1.0
    )
    pending_observation = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Pending item",
      status: :pending,
      relevance_weight: 1.0
    )

    get admin_observation_path(approved_observation)
    assert_response :success
    assert_includes @response.body, "Re-validate"
    assert_includes @response.body, revalidate_admin_observation_path(approved_observation)
    assert_includes @response.body, "Observations decay over time. Re-validate if it still applies."

    get admin_observation_path(pending_observation)
    assert_response :success
    refute_includes @response.body, "Re-validate"
  end

  test "prefixed revalidate turbo stream updates both dashboard and journal cards" do
    observation = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Prefixed turbo revalidate",
      status: :approved,
      relevance_weight: 1.0,
      last_validated_at: 2.months.ago
    )

    patch revalidate_admin_observation_path(observation),
      params: { frame_id_prefix: "obs_mgmt", entry_dom_id_prefix: "obs_mgmt" },
      as: :turbo_stream

    assert_response :success
    assert_includes @response.body, %(target="obs_mgmt_observation_#{observation.id}_card_container")
    assert_includes @response.body, %(target="observation_#{observation.id}_card_container")
  end

  test "prefixed destroy turbo stream removes both dashboard and journal cards" do
    observation = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Prefixed destroy",
      status: :approved,
      relevance_weight: 1.0
    )

    delete admin_observation_path(observation),
      params: { frame_id_prefix: "obs_mgmt", entry_dom_id_prefix: "obs_mgmt" },
      as: :turbo_stream

    assert_response :success
    assert_includes @response.body, %(target="obs_mgmt_observation_#{observation.id}_card_container")
    assert_includes @response.body, %(target="observation_#{observation.id}_card_container")
  end

  test "non-prefixed destroy turbo stream removes dashboard and journal cards" do
    observation = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Non-prefixed destroy",
      status: :approved,
      relevance_weight: 1.0
    )

    delete admin_observation_path(observation), as: :turbo_stream

    assert_response :success
    assert_includes @response.body, %(target="obs_mgmt_observation_#{observation.id}_card_container")
    assert_includes @response.body, %(target="observation_#{observation.id}_card_container")
  end
end
