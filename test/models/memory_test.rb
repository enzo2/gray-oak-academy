require "test_helper"

class MemoryTest < ActiveSupport::TestCase
  setup do
    @teacher = users(:admin)
    @other_teacher = users(:admin2)
    @superuser = users(:super_user)
    @student = users(:student)
  end

  test "author validation allows student teacher superuser or nil" do
    valid_authors = [ @student, @teacher, @superuser, nil ]

    valid_authors.each do |author|
      memory = Memory.new(student: @student, author: author, body: "Valid memory")
      assert memory.valid?, "Expected author #{author&.email || 'nil'} to be valid: #{memory.errors.full_messages.to_sentence}"
    end
  end

  test "author validation rejects unrelated teacher" do
    memory = Memory.new(student: @student, author: @other_teacher, body: "Unauthorized memory")

    assert_not memory.valid?
    assert_includes memory.errors[:author], "must be the student or their teacher"
  end

  test "for_prompt includes hidden marker and truncates output" do
    @student.memories.destroy_all
    @student.memories.create!(author: @teacher, body: "Visible memory", hidden_from_student: false)
    @student.memories.create!(author: @teacher, body: "Hidden memory", hidden_from_student: true)
    12.times do |i|
      @student.memories.create!(
        author: @teacher,
        body: "Long memory #{i}: " + ("x" * 4_450),
        hidden_from_student: false
      )
    end

    prompt = Memory.for_prompt(user: @student)

    assert_includes prompt, "Visible memory"
    assert_includes prompt, "Hidden memory"
    assert_includes prompt, "[hidden from student]"
    assert_operator prompt.length, :<=, 50_000
  end

  test "save updates embedding when body changes" do
    memory = Memory.new(student: @student, author: @teacher, body: "Needs embedding")
    update_called = false

    memory.stub(:update_embedding, -> { update_called = true }) do
      memory.save!
    end

    assert update_called
  end

  test "save does not update embedding when body is unchanged" do
    memory = memories(:three)
    update_called = false

    memory.stub(:update_embedding, -> { update_called = true }) do
      memory.update!(hidden_from_student: true)
    end

    assert_not update_called
  end
end
