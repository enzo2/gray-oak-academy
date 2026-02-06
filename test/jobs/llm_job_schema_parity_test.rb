require "test_helper"

class LlmJobSchemaParityTest < ActiveSupport::TestCase
  test "auto name conversation schema matches prior shape" do
    assert_equal "Conversation_Title", AutoNameConversationJob::TITLE_SCHEMA[:name]
    assert_equal true, AutoNameConversationJob::TITLE_SCHEMA[:strict]
    assert_equal(
      {
        "type" => "object",
        "properties" => {
          "title" => { "type" => "string" }
        },
        "required" => [ "title" ],
        "additionalProperties" => false
      },
      AutoNameConversationJob::TITLE_SCHEMA[:schema]
    )
  end

  test "generate observations schema matches prior shape" do
    assert_equal "Key_Observations", GenerateObservationsJob::OBSERVATIONS_SCHEMA[:name]
    assert_equal true, GenerateObservationsJob::OBSERVATIONS_SCHEMA[:strict]
    assert_equal(
      {
        "type" => "object",
        "properties" => {
          "observations" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "1-3 distinct, concise, high-value observations about the student's learning."
          }
        },
        "required" => [ "observations" ],
        "additionalProperties" => false
      },
      GenerateObservationsJob::OBSERVATIONS_SCHEMA[:schema]
    )
  end

  test "generate student profile schema matches prior shape" do
    assert_equal "Student_Profile", GenerateStudentProfileJob::PROFILE_SCHEMA[:name]
    assert_equal true, GenerateStudentProfileJob::PROFILE_SCHEMA[:strict]
    assert_equal(
      {
        "type" => "object",
        "properties" => {
          "current_snapshot" => {
            "type" => "string",
            "description" => "A concise summary of where the student currently stands academically and developmentally."
          },
          "learning_patterns" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "Observed patterns in how this student learns best (or struggles)."
          },
          "current_strengths" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "Areas where the student currently demonstrates proficiency or positive momentum."
          },
          "areas_for_focus" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "Areas that currently need attention, review, or different approaches."
          },
          "effective_approaches" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "Teaching methods, formats, or approaches that have proven effective."
          },
          "approaches_to_avoid" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "Methods or approaches that have been ineffective or counterproductive."
          },
          "recommendations" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "Specific, actionable recommendations for upcoming lessons or curriculum planning."
          }
        },
        "required" => [ "current_snapshot", "learning_patterns", "current_strengths", "areas_for_focus", "effective_approaches", "approaches_to_avoid", "recommendations" ],
        "additionalProperties" => false
      },
      GenerateStudentProfileJob::PROFILE_SCHEMA[:schema]
    )
  end

  test "generate course report schema matches prior shape" do
    assert_equal "Course_Report", GenerateCourseReportJob::REPORT_SCHEMA[:name]
    assert_equal true, GenerateCourseReportJob::REPORT_SCHEMA[:strict]
    assert_equal(
      {
        "type" => "object",
        "properties" => {
          "summary" => {
            "type" => "string",
            "description" => "A detailed overview of the student's performance and understanding during the course."
          },
          "strengths" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "List areas where the student demonstrated adequate-to-strong understanding, which will require minimal to no review in subsequent courses. May include knowledge, skills, abilities, or other learning targets."
          },
          "areas_for_review" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "List aspects (if any) of the course material/plan where the student should receive additional clarification, review or practice in subsequent courses or remedial sessions. May include knowledge, skills, abilities, or other learning targets."
          },
          "teaching_methods" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "Note any aspects of teaching methodology that were particularly effective or ineffective for the student."
          },
          "other_observations" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "Optional: Note any other observations or notable examples concerning the student's progress and development, such as engagement, attitude, cognition, or other relevant factors."
          }
        },
        "required" => [ "summary", "strengths", "areas_for_review", "teaching_methods", "other_observations" ],
        "additionalProperties" => false
      },
      GenerateCourseReportJob::REPORT_SCHEMA[:schema]
    )
  end

  test "backfill memories schema matches prior shape" do
    assert_equal "Merged_Memories", BackfillMemoriesFromLessonReportJob::MERGED_MEMORIES_SCHEMA[:name]
    assert_equal true, BackfillMemoriesFromLessonReportJob::MERGED_MEMORIES_SCHEMA[:strict]
    assert_equal(
      {
        "type" => "object",
        "properties" => {
          "new_memories" => {
            "type" => "array",
            "items" => { "type" => "string" }
          },
          "replacement_ids" => {
            "type" => "array",
            "items" => { "type" => "integer" }
          }
        },
        "required" => [ "new_memories", "replacement_ids" ],
        "additionalProperties" => false
      },
      BackfillMemoriesFromLessonReportJob::MERGED_MEMORIES_SCHEMA[:schema]
    )
  end

  test "generate course lessons schema matches prior shape" do
    assert_equal "Course_Lessons", GenerateCourseLessonsJob::LESSONS_SCHEMA[:name]
    assert_equal true, GenerateCourseLessonsJob::LESSONS_SCHEMA[:strict]
    assert_equal(
      {
        "type" => "object",
        "properties" => {
          "lessons" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "title" => { "type" => "string" },
                "goals" => { "type" => "string" },
                "duration" => { "type" => "integer" }
              },
              "required" => [ "title", "goals", "duration" ],
              "additionalProperties" => false
            }
          }
        },
        "required" => [ "lessons" ],
        "additionalProperties" => false
      },
      GenerateCourseLessonsJob::LESSONS_SCHEMA[:schema]
    )
  end

  test "generate lesson plan content schema matches prior shape" do
    assert_equal "Lesson_Plan", GenerateLessonPlanContentJob::CONTENT_SCHEMA[:name]
    assert_equal true, GenerateLessonPlanContentJob::CONTENT_SCHEMA[:strict]
    assert_equal(
      {
        "type" => "object",
        "properties" => {
          "lesson_plan" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "type" => { "type" => "string" },
                "details" => { "type" => "string" }
              },
              "required" => [ "type", "details" ],
              "additionalProperties" => false
            }
          },
          "suggested_resources" => {
            "type" => "array",
            "description" => "A list of suggested resources for the lesson which may need to be located, obtained or validated before use.",
            "items" => {
              "type" => "object",
              "properties" => {
                "type" => { "type" => "string" },
                "description" => { "type" => "string" }
              },
              "required" => [ "type", "description" ],
              "additionalProperties" => false
            }
          }
        },
        "required" => [ "lesson_plan", "suggested_resources" ],
        "additionalProperties" => false
      },
      GenerateLessonPlanContentJob::CONTENT_SCHEMA[:schema]
    )
  end
end
