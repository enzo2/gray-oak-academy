class AddGenerateStudentCourseReportToPromptCategory < ActiveRecord::Migration[8.0]
  def up
    add_enum_value :prompt_category, "generate_student_course_report", after: "generate_student_lesson_report"
  end
end
