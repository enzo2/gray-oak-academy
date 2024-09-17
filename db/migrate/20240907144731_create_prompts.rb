class CreatePrompts < ActiveRecord::Migration[7.2]
  def change
    create_enum :prompt_category, [ "other", # default category
                                    "generate_lessons",
                                    "generate_lesson_plan",
                                    "suggest_resources",
                                    "lesson_tutor_session",
                                    "open_ended_student_chat",
                                    "student_progress_tutor_session",
                                    "generate_student_lesson_report",
                                    "generate_student_assessment_report",
                                    "generate_student_profile",
                                    "tool_usage",
                                    "teacher_assistant",
                                    "teaching_principles",
                                    "base_system_prompt"
                                  ]

    create_table :prompts do |t|
      t.string :title
      t.enum :category, enum_type: :prompt_category, default: "other", null: false
      t.text :prompt
      t.references :teacher, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
