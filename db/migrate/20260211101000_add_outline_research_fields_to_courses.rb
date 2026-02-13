class AddOutlineResearchFieldsToCourses < ActiveRecord::Migration[8.1]
  def change
    add_column :courses, :outline_research_stage, :string, default: "idle", null: false
    add_column :courses, :outline_research_error, :text
    add_column :courses, :outline_research, :jsonb, default: {}, null: false
    add_column :courses, :outline_guidance_report_md, :text
    add_column :courses, :outline_guidance_questions, :jsonb, default: [], null: false
    add_column :courses, :outline_guidance_answers, :jsonb, default: {}, null: false
    add_column :courses, :outline_research_run_id, :string
    add_column :courses, :outline_research_response_id, :string
    add_column :courses, :course_prior_state, :jsonb, default: {}, null: false

    add_index :courses, :outline_research_stage
  end
end
