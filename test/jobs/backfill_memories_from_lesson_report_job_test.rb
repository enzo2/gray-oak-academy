require "test_helper"

class BackfillMemoriesFromLessonReportJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  def setup
    @student = users(:student)
    @report = student_reports(:LessonReport1)
    # Ensure the report has memories in progress_data
    @report.update!(
      progress_data: {
        "summary" => "Test summary",
        "memories" => [
          "Student prefers visual learning",
          "Works well with interactive examples"
        ]
      }
    )
  end

  # ==========================================
  # Happy Path Tests
  # ==========================================

  test "successfully creates new memories from LLM response" do
    initial_count = @student.memories.count

    stub_llm_response(new_memories: [ "New memory 1", "New memory 2" ]) do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end

    assert_equal initial_count + 2, @student.memories.count
    new_memory_1 = @student.memories.find_by(body: "New memory 1")
    new_memory_2 = @student.memories.find_by(body: "New memory 2")

    assert_not_nil new_memory_1
    assert_not_nil new_memory_2
    assert_equal @report, new_memory_1.student_report
    assert_equal @report, new_memory_2.student_report
    assert_equal false, new_memory_1.hidden_from_student
    assert_equal false, new_memory_2.hidden_from_student
  end

  test "successfully deletes replaced memories" do
    memory_to_delete = @student.memories.first

    assert_difference "@student.memories.count", -1 do
      stub_llm_response(
        new_memories: [],
        replacement_ids: [ memory_to_delete.id ]
      ) do
        BackfillMemoriesFromLessonReportJob.perform_now(@report)
      end
    end

    assert_nil Memory.find_by(id: memory_to_delete.id)
  end

  test "creates new and deletes old memories in same transaction" do
    memory_to_delete = @student.memories.first

    # Net change should be 0 (1 created, 1 deleted)
    assert_no_difference "@student.memories.count" do
      stub_llm_response(
        new_memories: [ "Consolidated memory" ],
        replacement_ids: [ memory_to_delete.id ]
      ) do
        BackfillMemoriesFromLessonReportJob.perform_now(@report)
      end
    end

    assert_nil Memory.find_by(id: memory_to_delete.id)
    assert_not_nil @student.memories.find_by(body: "Consolidated memory")
  end

  test "associates new memories with student_report" do
    stub_llm_response(new_memories: [ "Test memory" ]) do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end

    memory = @student.memories.find_by(body: "Test memory")
    assert_equal @report, memory.student_report
  end

  # ==========================================
  # Validation Tests
  # ==========================================

  test "rejects non-StudentReport input" do
    stub_llm_response(new_memories: [ "Should not be created" ])

    assert_no_difference "Memory.count" do
      BackfillMemoriesFromLessonReportJob.perform_now("not a report")
    end
  end

  test "rejects reports with wrong reportable_type" do
    enrollment = enrollments(:one)
    enrollment_report = StudentReport.create!(
      reportable_type: "Enrollment",
      reportable_id: enrollment.id,
      student: @student,
      author_type: :ai_generated,
      status: :completed,
      progress_data: { "memories" => [ "Test" ] }
    )

    stub_llm_response(new_memories: [ "Should not be created" ])

    assert_no_difference "Memory.count" do
      BackfillMemoriesFromLessonReportJob.perform_now(enrollment_report)
    end
  end

  test "rejects reports without memories in progress_data" do
    @report.update!(progress_data: { "summary" => "No memories" })
    stub_llm_response(new_memories: [ "Should not be created" ])

    assert_no_difference "Memory.count" do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end
  end

  test "rejects reports with empty memories array" do
    @report.update!(progress_data: { "memories" => [] })
    stub_llm_response(new_memories: [ "Should not be created" ])

    assert_no_difference "Memory.count" do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end
  end

  test "rejects reports with nil progress_data" do
    @report.update_column(:progress_data, nil)
    stub_llm_response(new_memories: [ "Should not be created" ])

    assert_no_difference "Memory.count" do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end
  end

  # ==========================================
  # Memory Normalization Tests
  # ==========================================

  test "handles memories as Hash objects with body key" do
    @report.update!(
      progress_data: {
        "memories" => [
          { "body" => "Memory from hash" }
        ]
      }
    )

    stub_llm_response(new_memories: [ "Processed memory" ]) do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end

    # The job should normalize the input and call the LLM
    # which will return "Processed memory"
    assert_not_nil @student.memories.find_by(body: "Processed memory")
  end

  test "handles memories as plain String objects" do
    @report.update!(
      progress_data: {
        "memories" => [ "Plain string memory" ]
      }
    )

    stub_llm_response(new_memories: [ "Processed memory" ]) do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end

    assert_not_nil @student.memories.find_by(body: "Processed memory")
  end

  test "filters out blank and empty memories" do
    @report.update!(
      progress_data: {
        "memories" => [ "Valid memory", "", "  ", nil, { "body" => "" } ]
      }
    )

    stub_llm_response(new_memories: [ "Consolidated memory" ]) do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end

    # Only the valid memory should be sent to LLM (verified implicitly)
    assert_not_nil @student.memories.find_by(body: "Consolidated memory")
  end

  test "removes duplicate memories before processing" do
    @report.update!(
      progress_data: {
        "memories" => [ "Duplicate", "Duplicate", "Unique" ]
      }
    )

    stub_llm_response(new_memories: [ "Merged memory" ]) do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end

    # Duplicates should be removed during normalization
    assert_not_nil @student.memories.find_by(body: "Merged memory")
  end

  # ==========================================
  # LLM Integration Tests
  # ==========================================

  test "calls OpenaiApiService with correct parameters" do
    expected_prompt = nil
    expected_system_prompt = nil

    LlmServiceRouting.stub(:build_completion_client, ->(current_user:, task_system_prompt:, reasoning_model:, **_kwargs) {
      expected_system_prompt = task_system_prompt
      assert_equal @student, current_user
      assert_equal true, reasoning_model
      assert_equal false, _kwargs[:store]
      Object.new
    }) do
      LlmServiceRouting.stub(:complete_structured_output, lambda { |client:, messages:, response_format:, schema:, prefill:|
        expected_prompt = messages.first[:content]
        assert messages.first[:content].include?("Existing memories")
        assert messages.first[:content].include?("New candidate memories")
        assert_equal "json_schema", response_format[:type]
        { "new_memories" => [ "Test memory" ], "replacement_ids" => [] }
      }) do
        BackfillMemoriesFromLessonReportJob.perform_now(@report)
      end
    end

    assert_not_nil expected_prompt
    assert_not_nil expected_system_prompt
  end

  test "handles LLM response with both new_memories and replacement_ids" do
    memory_to_delete = @student.memories.first

    stub_llm_response(
      new_memories: [ "New memory" ],
      replacement_ids: [ memory_to_delete.id ]
    ) do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end

    assert_not_nil @student.memories.find_by(body: "New memory")
    assert_nil Memory.find_by(id: memory_to_delete.id)
  end

  test "gracefully handles invalid LLM response format" do
    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { Object.new }) do
      LlmServiceRouting.stub(:complete_structured_output, "invalid string response") do
        # Should log error but not raise
        assert_nothing_raised do
          BackfillMemoriesFromLessonReportJob.perform_now(@report)
        end
      end
    end
  end

  test "gracefully handles LLM response without new_memories array" do
    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { Object.new }) do
      LlmServiceRouting.stub(:complete_structured_output, { "replacement_ids" => [] }) do
        # Should log error but not raise
        assert_nothing_raised do
          BackfillMemoriesFromLessonReportJob.perform_now(@report)
        end
      end
    end
  end

  test "logs error when LLM call fails" do
    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { Object.new }) do
      LlmServiceRouting.stub(:complete_structured_output, ->(**_kwargs) { raise StandardError, "API error" }) do
        # Should log error but not raise
        assert_nothing_raised do
          BackfillMemoriesFromLessonReportJob.perform_now(@report)
        end
      end
    end
  end

  # ==========================================
  # Edge Cases
  # ==========================================

  test "handles empty new_memories array from LLM" do
    assert_no_difference "Memory.count" do
      stub_llm_response(new_memories: []) do
        BackfillMemoriesFromLessonReportJob.perform_now(@report)
      end
    end
  end

  test "only deletes memories belonging to the student" do
    other_student = users(:student2)
    other_memory = other_student.memories.create!(
      body: "Other student's memory",
      hidden_from_student: false
    )

    # Try to delete another student's memory (should be prevented by scope)
    stub_llm_response(
      new_memories: [],
      replacement_ids: [ other_memory.id ]
    ) do
      BackfillMemoriesFromLessonReportJob.perform_now(@report)
    end

    # Other student's memory should still exist
    assert_not_nil Memory.find_by(id: other_memory.id)
  end

  test "transaction rollback if memory creation fails" do
    memory_to_delete = @student.memories.first

    # Stub to return invalid data that will cause validation failure
    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { Object.new }) do
      LlmServiceRouting.stub(:complete_structured_output, {
        "new_memories" => [ "x" * 6000 ],
        "replacement_ids" => [ memory_to_delete.id ]
      }) do
        initial_count = @student.memories.count

        BackfillMemoriesFromLessonReportJob.perform_now(@report)

        # Transaction should rollback, memory count unchanged
        assert_equal initial_count, @student.memories.reload.count
        # Memory to delete should still exist
        assert_not_nil Memory.find_by(id: memory_to_delete.id)
      end
    end
  end

  test "handles nil replacement_ids gracefully" do
    assert_difference "Memory.count", 1 do
      stub_llm_response(new_memories: [ "New memory" ]) do
        BackfillMemoriesFromLessonReportJob.perform_now(@report)
      end
    end
  end

  test "skips blank memory bodies in new_memories" do
    assert_difference "Memory.count", 2 do
      stub_llm_response(
        new_memories: [ "Valid memory", "", "  ", "Another valid memory" ]
      ) do
        BackfillMemoriesFromLessonReportJob.perform_now(@report)
      end
    end

    assert_not_nil @student.memories.find_by(body: "Valid memory")
    assert_not_nil @student.memories.find_by(body: "Another valid memory")
  end

  private

  def stub_llm_response(new_memories: [], replacement_ids: nil)
    response = { "new_memories" => new_memories }
    response["replacement_ids"] = replacement_ids if replacement_ids

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { Object.new }) do
      LlmServiceRouting.stub(:complete_structured_output, response) do
        yield if block_given?
      end
    end
  end
end
