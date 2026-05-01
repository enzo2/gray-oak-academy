module TeacherAgent
  class HelpTopicCatalog
    TOPICS = {
      "curriculum_workflow" => {
        description: "Overall course, outline, lesson, lesson-plan, resource, and teacher-review workflow.",
        guidance: [
          "Use read commands before write commands so edits are based on current IDs and persisted state.",
          "Courses contain metadata and an outline; lessons belong to courses; each lesson may have one lesson plan.",
          "Course outlines are topic/skill scopes, not necessarily a one-to-one list of lessons.",
          "Lesson plans are drafts until a teacher publishes them in Gray Oak Academy. External agents cannot publish lesson plans.",
          "Generated or agent-created resources generally require teacher review before student use."
        ]
      },
      "course_outlines" => {
        description: "Course outline generation and outline research guidance.",
        guidance: [
          "Create or update course summary and grade level before generating an outline.",
          "Write outline updates as an array of objects shaped like `{ \"topic\": \"...\", \"description\": \"...\" }`.",
          "Read responses return outlines as single-key hashes because that is the stored lesson-planning shape.",
          "Outline research may pause at `awaiting_teacher_input`; stop there and ask the teacher to answer in Gray Oak Academy."
        ]
      },
      "lessons" => {
        description: "Lesson shell generation guidance.",
        guidance: [
          "Generate lessons after the course outline is acceptable.",
          "Lessons should cover the course scope at the grade level without assuming a strict one-to-one mapping to outline topics.",
          "Manual lesson edits can create, update, delete, or reorder lesson shells.",
          "Deleting a lesson through the Agent API is blocked when that lesson already has a lesson plan."
        ]
      },
      "quick_lessons" => {
        description: "One-off teacher-reviewable lessons that do not clutter full-course planning.",
        guidance: [
          "Use `create_quick_lesson` instead of creating a course when the teacher asks for a quick, one-off, or just-in-time lesson.",
          "Quick lessons are backed by hidden single-lesson courses so normal lesson plans, resources, applets, reports, memories, and observations still work.",
          "Students assigned through `student_ids` cannot start the lesson until the teacher publishes the lesson plan in Gray Oak Academy.",
          "Quick lessons do not generate course-level completion reports."
        ]
      },
      "lesson_plans" => {
        description: "Lesson-plan content structure and generation guidance.",
        guidance: [
          "Always call `get_lesson` before editing a lesson plan.",
          "`update_lesson_plan_draft` replaces the full lesson-plan content array; do not send partial patches.",
          "Write lesson-plan content as an array of `{ \"type\": \"...\", \"details\": \"...\" }`; read responses return single-key hashes.",
          "Write suggested resources as an array of `{ \"type\": \"...\", \"description\": \"...\" }`; read responses return single-key hashes.",
          "External agents can create or update draft plans only. Published plans are locked for Agent API edits.",
          "`audio` accepts `enabled` or `audio-only`; `chalkboard_enabled` is a boolean."
        ]
      },
      "resources" => {
        description: "Resource proposal, verification, linking, and review guidance.",
        guidance: [
          "Resources can be URI, text content, uploaded file, or applet payloads.",
          "`create_resource` requires exactly one payload: `uri`, `content`, `file_base64`, or `applet_attributes`.",
          "For file uploads, provide strict Base64 plus `filename` and `content_type`.",
          "Agent-created resources default to pending approval unless `approve` is true.",
          "Do not link a pending resource to a published lesson plan.",
          "Only approve resources after checking relevance, source quality, and teacher intent."
        ]
      },
      "applets" => {
        description: "Executable JavaScript applet runtime, structure, and safety requirements.",
        guidance: [
          "Saved applet `code` must be raw JavaScript module code, not a Markdown fenced code block.",
          "Applet code runs in a sandboxed iframe and should mount UI into `document.getElementById(\"sandbox\")`.",
          "TailwindCSS is loaded in the iframe.",
          "React 18, p5.js, and Three.js are available through import maps: import React from `react`, ReactDOM from `react-dom/client`, p5 from `p5`, and Three as `three`.",
          "JSX is not supported; use plain JavaScript or `React.createElement`.",
          "Do not use microphone or camera APIs.",
          "Do not invent external image, dataset, script, or media URLs; use only URLs explicitly provided by lesson/resource context.",
          "Applet saves are syntax checked, but agents should still design complete UI and behavior before calling `upsert_applet`."
        ]
      },
      "student_progress" => {
        description: "Student progress profile and observation guidance.",
        guidance: [
          "Use `list_students` before student-specific work so names and IDs are not guessed.",
          "Use `get_student_profile` for a teacher-facing synthesis of recent progress, observations, memories, feedback, and reports.",
          "Use `get_student_reports` when lesson or course report details are needed.",
          "External agents should not message students, conduct lessons, or approve observations."
        ]
      }
    }.freeze

    COMMAND_TOPICS = {
      "list_students" => %w[student_progress],
      "get_student_profile" => %w[student_progress],
      "get_student_reports" => %w[student_progress],
      "list_courses" => %w[curriculum_workflow],
      "get_course" => %w[curriculum_workflow course_outlines lessons],
      "create_course" => %w[curriculum_workflow course_outlines],
      "update_course" => %w[curriculum_workflow course_outlines],
      "generate_course_outline" => %w[curriculum_workflow course_outlines],
      "generate_course_lessons" => %w[curriculum_workflow lessons],
      "list_quick_lessons" => %w[quick_lessons lesson_plans student_progress],
      "create_quick_lesson" => %w[quick_lessons lesson_plans resources applets student_progress],
      "edit_course_lessons" => %w[curriculum_workflow lessons],
      "get_lesson" => %w[curriculum_workflow lesson_plans resources applets],
      "update_lesson_plan_draft" => %w[curriculum_workflow lesson_plans resources applets],
      "generate_lesson_plan" => %w[curriculum_workflow lesson_plans resources applets],
      "propose_lesson_resources" => %w[resources applets],
      "list_resources" => %w[resources],
      "get_resource" => %w[resources applets],
      "create_resource" => %w[resources applets],
      "update_resource" => %w[resources applets],
      "link_resource_to_lesson_plan" => %w[resources lesson_plans],
      "unlink_resource_from_lesson_plan" => %w[resources lesson_plans],
      "approve_resource" => %w[resources],
      "list_applets" => %w[applets],
      "get_applet" => %w[applets],
      "upsert_applet" => %w[applets],
      "save_applet_as_resource" => %w[applets resources]
    }.freeze

    def self.topics
      TOPICS.transform_values do |topic|
        topic.slice(:description)
      end
    end

    def self.topic(name)
      name = name.to_s
      details = TOPICS[name]
      return nil unless details

      {
        name: name,
        description: details[:description],
        guidance: details[:guidance]
      }
    end

    def self.command_topics(command)
      COMMAND_TOPICS.fetch(command.to_s, [])
    end
  end
end
