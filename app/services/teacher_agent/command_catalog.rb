module TeacherAgent
  class CommandCatalog
    COMMANDS = {
      "status" => {
        description: "Return API and teacher identity status.",
        args: {}
      },
      "list_students" => {
        description: "List students owned by this teacher.",
        args: {}
      },
      "get_student_profile" => {
        description: "Return a teacher-facing student profile summary.",
        args: { student_id: "integer", focus: "optional string" }
      },
      "get_student_reports" => {
        description: "Return completed lesson/course reports for one student.",
        args: { student_id: "integer" }
      },
      "list_courses" => {
        description: "List courses owned by this teacher.",
        args: {}
      },
      "get_course" => {
        description: "Return course outline and lesson summary.",
        args: { course_id: "integer" }
      },
      "create_course" => {
        description: "Create a course shell.",
        args: { title: "string", summary: "string", grade_level: "string" }
      },
      "update_course" => {
        description: "Update course metadata and optional outline.",
        args: { course_id: "integer", title: "optional string", summary: "optional string", grade_level: "optional string", outline: "optional array of {topic, description}" }
      },
      "generate_course_outline" => {
        description: "Generate or queue research for a course outline.",
        args: { course_id: "integer", action: "generate_outline | research_outline | generate_and_research" },
        guidance: [
          "Call get_course first so the current summary, grade level, outline, and research stage are known.",
          "research_outline and generate_and_research may return queued work. Use the returned poll command to check status.",
          "If outline research reaches awaiting_teacher_input, stop and tell the teacher to answer the guidance questions in Gray Oak Academy. Do not answer them yourself."
        ]
      },
      "generate_course_lessons" => {
        description: "Generate lessons from the current course outline.",
        args: { course_id: "integer", replace_existing_lessons: "optional boolean" }
      },
      "edit_course_lessons" => {
        description: "Create, update, delete, or reorder lesson shells.",
        args: { course_id: "integer", lessons_to_create: "optional array", lessons_to_update: "optional array", lessons_to_delete: "optional array of IDs", lessons_order: "optional array of {id, position}" }
      },
      "get_lesson" => {
        description: "Return a lesson and its draft/published lesson plan.",
        args: { lesson_id: "integer" }
      },
      "update_lesson_plan_draft" => {
        description: "Create or update lesson plan draft content. Publishing is forbidden.",
        args: { lesson_id: "integer", lesson_plan_content: "optional array of {type, details}", suggested_resources: "optional array of {type, description}", audio: "optional enabled | audio-only", chalkboard_enabled: "optional boolean" },
        guidance: [
          "Always call get_lesson first.",
          "lesson_plan_content is a complete replacement array, not a patch. Include all content items that should remain.",
          "suggested_resources is also a complete replacement array when provided.",
          "Write content items as {type, details}; read responses return stored single-key hashes like {\"Warmup\":\"...\"}.",
          "External agents cannot publish lesson plans or edit published plans."
        ],
        example_args: {
          lesson_id: 123,
          lesson_plan_content: [
            { type: "Warmup", details: "Ask what the student already knows about the topic." },
            { type: "Guided Practice", details: "Work through two examples with increasing independence." }
          ],
          suggested_resources: [
            { type: "Applet", description: "Interactive visualization for the central concept." }
          ],
          audio: "enabled",
          chalkboard_enabled: true
        }
      },
      "generate_lesson_plan" => {
        description: "Generate lesson-plan content or queue resource proposals.",
        args: { lesson_id: "integer", action: "generate_content | propose_resources_async | generate_content_and_propose_resources_async" },
        guidance: [
          "generate_content runs synchronously and replaces existing lesson_plan.content.",
          "propose_resources_async and generate_content_and_propose_resources_async queue background work; use the returned poll command.",
          "Resource proposal may create pending resources/applets for teacher review."
        ]
      },
      "propose_lesson_resources" => {
        description: "Queue resource proposals for one lesson plan. Async agent run will search the web for digital resources, and may write JavaScript applets.",
        args: { lesson_id: "integer" }
      },
      "list_resources" => {
        description: "List teacher resources, optionally filtered by approval.",
        args: { approved: "optional true | false | human", lesson_plan_id: "optional integer" }
      },
      "get_resource" => {
        description: "Return resource metadata and payload preview.",
        args: { resource_id: "integer" }
      },
      "create_resource" => {
        description: "Create a teacher-owned URI, text, applet, or base64-file resource. Agent-created resources default to pending approval.",
        args: { description: "string", category: "optional string", uri: "optional string", content: "optional string", file_base64: "optional string", filename: "required with file_base64", content_type: "required with file_base64", applet_attributes: "optional {title, code}", lesson_id: "optional integer", tags: "optional array or comma string", approve: "optional boolean" },
        guidance: [
          "Provide exactly one payload: uri, content, file_base64, or applet_attributes.",
          "For file_base64, provide strict Base64 plus filename and content_type.",
          "For applet_attributes, code must be raw JavaScript module code, not a Markdown fenced block.",
          "Resources created by agents default to pending approval unless approve is true.",
          "Pending resources cannot be linked to published lesson plans."
        ]
      },
      "update_resource" => {
        description: "Update non-destructive metadata or replace a text/URI/file payload for a teacher-owned resource.",
        args: { resource_id: "integer", description: "optional string", category: "optional string", tags: "optional array or comma string", include_by_default: "optional boolean", uri: "optional string", content: "optional string", file_base64: "optional string", filename: "required with file_base64", content_type: "required with file_base64" }
      },
      "link_resource_to_lesson_plan" => {
        description: "Link a resource to a teacher-owned lesson plan.",
        args: { lesson_plan_id: "integer", resource_id: "integer" }
      },
      "unlink_resource_from_lesson_plan" => {
        description: "Unlink a resource from a teacher-owned lesson plan.",
        args: { lesson_plan_id: "integer", resource_id: "integer" }
      },
      "approve_resource" => {
        description: "Approve a pending teacher-owned resource.",
        args: { resource_id: "integer" }
      },
      "list_applets" => {
        description: "List teacher applets.",
        args: {}
      },
      "get_applet" => {
        description: "Return applet code.",
        args: { applet_id: "integer" }
      },
      "upsert_applet" => {
        description: "Create or update a teacher applet.",
        args: { applet_id: "optional integer", title: "string for create or optional for update", code: "string for create or optional for update" },
        guidance: [
          "code must be raw JavaScript module code only; do not include Markdown fences or executable-block attributes.",
          "Applet code runs in a sandboxed iframe. Mount UI into document.getElementById(\"sandbox\").",
          "JSX is not supported. Use plain JavaScript or React.createElement.",
          "TailwindCSS is available. React, ReactDOM, p5, and Three.js are available via import maps.",
          "Do not use microphone/camera APIs or invented external URLs.",
          "The API syntax-checks JavaScript, but it cannot verify visual quality or runtime behavior."
        ],
        example_args: {
          title: "Balance Scale Explorer",
          code: "const sandbox = document.getElementById('sandbox');\nsandbox.innerHTML = '<div class=\"font-sans p-4\"><h1 class=\"text-xl font-bold\">Balance Scale Explorer</h1></div>';"
        }
      },
      "save_applet_as_resource" => {
        description: "Save an applet as a pending resource, optionally linked to a lesson.",
        args: { applet_id: "integer", lesson_id: "optional integer" }
      }
    }.freeze

    def self.commands
      COMMANDS
    end

    def self.command(name)
      COMMANDS[name.to_s]
    end

    def self.allowed?(name)
      COMMANDS.key?(name.to_s)
    end
  end
end
