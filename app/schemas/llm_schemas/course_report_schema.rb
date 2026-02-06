module LlmSchemas
  class CourseReportSchema < OpenAI::BaseModel
    required :summary, String, doc: "A detailed overview of the student's performance and understanding during the course."
    required :strengths, OpenAI::ArrayOf[String], doc: "List areas where the student demonstrated adequate-to-strong understanding, which will require minimal to no review in subsequent courses. May include knowledge, skills, abilities, or other learning targets."
    required :areas_for_review, OpenAI::ArrayOf[String], doc: "List aspects (if any) of the course material/plan where the student should receive additional clarification, review or practice in subsequent courses or remedial sessions. May include knowledge, skills, abilities, or other learning targets."
    required :teaching_methods, OpenAI::ArrayOf[String], doc: "Note any aspects of teaching methodology that were particularly effective or ineffective for the student."
    required :other_observations, OpenAI::ArrayOf[String], doc: "Optional: Note any other observations or notable examples concerning the student's progress and development, such as engagement, attitude, cognition, or other relevant factors."
  end
end
