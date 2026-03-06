require "test_helper"

class Admin::MemoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:admin)
    @student = users(:student)
    @other_student = users(:student2)
    @other_student.update!(teacher: users(:admin2))
  end

  test "teacher can create and toggle hidden on own student memory" do
    sign_in @teacher

    assert_difference("Memory.count", 1) do
      post admin_student_memories_path(@student),
           params: { memory: { body: "Tracks better with diagrams", hidden_from_student: "0" } },
           as: :turbo_stream
    end

    memory = Memory.order(:created_at).last
    assert_equal @student, memory.student
    assert_equal @teacher, memory.author
    assert_not memory.hidden_from_student?

    patch toggle_hidden_admin_student_memory_path(@student, memory), as: :turbo_stream

    assert_response :success
    assert memory.reload.hidden_from_student?
  end

  test "teacher can create memory for self dashboard" do
    sign_in @teacher

    assert_difference("Memory.count", 1) do
      post admin_student_memories_path(@teacher),
           params: { memory: { body: "Self note for teacher dashboard", hidden_from_student: "1" } },
           as: :turbo_stream
    end

    memory = Memory.order(:created_at).last
    assert_equal @teacher, memory.student
    assert_equal @teacher, memory.author
    assert memory.hidden_from_student?
    assert_response :success
  end

  test "teacher cannot create memory for another teachers student" do
    sign_in @teacher

    assert_no_difference("Memory.count") do
      post admin_student_memories_path(@other_student),
           params: { memory: { body: "Unauthorized memory" } },
           as: :turbo_stream
    end

    assert_response :not_found
  end

  test "teacher cannot edit another teachers student memory" do
    sign_in @teacher

    get edit_admin_student_memory_path(@other_student, memories(:two)), as: :turbo_stream

    assert_response :not_found
  end

  test "teacher cannot toggle another teachers student memory" do
    sign_in @teacher

    patch toggle_hidden_admin_student_memory_path(@other_student, memories(:two)), as: :turbo_stream

    assert_response :not_found
  end
end
