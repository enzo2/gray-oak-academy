require "test_helper"

class DefaultSeedRefreshServiceTest < ActiveSupport::TestCase
  test "refresh deletes default prompts and tools but preserves teacher prompts" do
    teacher = users(:admin)

    default_prompt = Prompt.create!(
      title: "Stale Default Teacher Assistant",
      category: "teacher_assistant",
      prompt: "stale default",
      teacher_id: nil
    )
    teacher_prompt = Prompt.create!(
      title: "Custom Teacher Assistant",
      category: "teacher_assistant",
      prompt: "teacher customized",
      teacher: teacher
    )
    old_tool = Tool.create!(
      specifications: {
        "name" => "Old_Seeded_Tool",
        "description" => "Old seeded tool",
        "parameters" => {
          "type" => "object",
          "properties" => {}
        }
      }
    )

    seed_loader = -> do
      Prompt.create!(
        title: "Fresh Default Teacher Assistant",
        category: "teacher_assistant",
        prompt: "fresh default",
        teacher_id: nil
      )
      Tool.create!(
        specifications: {
          "name" => "Fresh_Seeded_Tool",
          "description" => "Fresh seeded tool",
          "parameters" => {
            "type" => "object",
            "properties" => {}
          }
        }
      )
    end

    result = DefaultSeedRefreshService.call(seed_loader:, output: StringIO.new)

    assert_operator result.tools_deleted, :>=, 1
    assert_operator result.default_prompts_deleted, :>=, 1
    assert_not Prompt.exists?(default_prompt.id)
    assert_not Tool.exists?(old_tool.id)
    assert_equal "teacher customized", teacher_prompt.reload.prompt
    assert_equal "fresh default", Prompt.find_by!(category: "teacher_assistant", teacher_id: nil).prompt
    assert Tool.exists?(name: "Fresh_Seeded_Tool")
  end

  test "refresh rolls back deleted defaults when seed reload fails" do
    default_prompt = Prompt.create!(
      title: "Default To Preserve",
      category: "teacher_assistant",
      prompt: "still here",
      teacher_id: nil
    )
    old_tool = Tool.create!(
      specifications: {
        "name" => "Tool_To_Preserve",
        "description" => "Seeded tool to preserve on failure",
        "parameters" => {
          "type" => "object",
          "properties" => {}
        }
      }
    )

    seed_loader = -> { raise "seed failed" }

    assert_raises RuntimeError do
      DefaultSeedRefreshService.call(seed_loader:, output: StringIO.new)
    end

    assert Prompt.exists?(default_prompt.id)
    assert Tool.exists?(old_tool.id)
  end
end
