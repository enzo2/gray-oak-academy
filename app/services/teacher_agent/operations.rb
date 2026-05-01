require "base64"
require "stringio"
require "set"

module TeacherAgent
  class Operations
    class Error < StandardError
      attr_reader :code, :http_status

      def initialize(message, code: "operation_failed", http_status: :unprocessable_content)
        super(message)
        @code = code
        @http_status = http_status
      end
    end

    attr_reader :teacher, :touched_records

    def initialize(teacher:)
      @teacher = teacher
      @touched_records = Hash.new { |hash, key| hash[key] = [] }
      raise Error.new("Agent API access requires a teacher account.", code: "teacher_required", http_status: :forbidden) unless teacher&.role_teacher?
    end

    def status(_args = {})
      {
        teacher: user_payload(teacher),
        api_version: "v1",
        capabilities: {
          can_prepare_curriculum: true,
          can_create_draft_lesson_plans: true,
          can_publish_lesson_plans: false,
          can_conduct_lessons: false,
          can_message_students: false,
          can_approve_resources: true
        },
        commands: TeacherAgent::CommandCatalog.commands.keys
      }
    end

    def list_students(_args = {})
      student_scope.select(:id, :first_name, :last_name, :email, :role).map { |student| user_payload(student) }
    end

    def get_student_reports(args)
      student = find_student!(args["student_id"])
      reports = student.student_reports.where(teacher: teacher).order(created_at: :desc)
      {
        student: user_payload(student),
        report_counts: { lessons: reports.lesson_reports.count, courses: reports.course_reports.count },
        reports_markdown: reports.map(&:to_markdown).join("\n\n---\n\n")
      }
    end

    def get_student_profile(args)
      student = find_student!(args["student_id"])
      focus = args["focus"].to_s.strip.presence
      profile = build_student_profile(student, focus: focus)
      { student: user_payload(student), focus: focus, profile_markdown: profile }
    end

    def list_courses(_args = {})
      course_scope.select(:id, :title, :summary, :grade_level, :status, :created_at, :updated_at)
                  .order(created_at: :desc)
                  .map { |course| course_summary(course) }
    end

    def get_course(args)
      course = find_course!(args["course_id"])
      touch(course)
      course.for_llm
    end

    def create_course(args)
      course = teacher.taught_courses.new(
        title: required_string(args, "title"),
        summary: required_string(args, "summary"),
        grade_level: required_string(args, "grade_level")
      )
      save_record!(course)
      touch(course)
      { course: course.for_llm }
    end

    def update_course(args)
      course = find_course!(args["course_id"])
      raise Error.new("Course edits are locked while outline research is in progress.", code: "course_locked", http_status: :conflict) if course.outline_research_in_progress?

      Course.transaction do
        course.title = args["title"] if args["title"].present?
        course.summary = args["summary"] if args["summary"].present?
        course.grade_level = args["grade_level"] if args["grade_level"].present?
        course.outline = normalize_outline(args["outline"]) if args.key?("outline")
        save_record!(course)
      end

      touch(course)
      { course: course.reload.for_llm }
    end

    def generate_course_outline(args)
      course = find_course!(args["course_id"])
      action = args["action"].to_s.presence || "generate_outline"

      case action
      when "generate_outline"
        GenerateCourseOutlineJob.perform_now(course, teacher, raise_on_error: true)
        touch(course)
        { status: "completed", action: action, course: course.reload.for_llm }
      when "research_outline"
        result = CourseOutlineResearchAsyncService.new(course: course, current_user: teacher, source: "agent_api").enqueue_start
        raise Error.new(result[:message], code: "queue_failed") unless result[:ok]

        touch(course)
        { status: "queued", action: action, message: result[:message], course_id: course.id, outline_research_stage: course.reload.outline_research_stage, poll: { command: "get_course", args: { course_id: course.id } } }
      when "generate_and_research"
        GenerateCourseOutlineJob.perform_now(course, teacher, raise_on_error: true)
        result = CourseOutlineResearchAsyncService.new(course: course.reload, current_user: teacher, source: "agent_api").enqueue_start
        raise Error.new(result[:message], code: "queue_failed") unless result[:ok]

        touch(course)
        { status: "queued", action: action, message: result[:message], course: course.reload.for_llm, poll: { command: "get_course", args: { course_id: course.id } } }
      else
        raise Error.new("Unknown action: #{action}", code: "invalid_action")
      end
    end

    def generate_course_lessons(args)
      course = find_course!(args["course_id"])
      replace = ActiveModel::Type::Boolean.new.cast(args["replace_existing_lessons"])
      GenerateCourseLessonsJob.perform_now(course, teacher, replace_existing_lessons: replace, raise_on_error: true)
      touch(course)
      { status: "completed", course: course.reload.for_llm }
    end

    def edit_course_lessons(args)
      course = find_course!(args["course_id"])

      Course.transaction do
        Array(args["lessons_to_delete"]).each do |lesson_id|
          lesson = course.lessons.find_by(id: lesson_id)
          raise Error.new("Lesson #{lesson_id} not found in course #{course.id}", code: "not_found", http_status: :not_found) unless lesson
          raise Error.new("Cannot delete lesson #{lesson.id} because it has a lesson plan.", code: "lesson_plan_exists", http_status: :conflict) if lesson.lesson_plan.present?

          lesson.destroy!
          touch(lesson)
        end

        Array(args["lessons_to_update"]).each do |item|
          lesson = course.lessons.find_by(id: item["id"].to_i)
          raise Error.new("Lesson #{item['id']} not found in course #{course.id}", code: "not_found", http_status: :not_found) unless lesson

          lesson.title = item["title"] if item["title"].present?
          lesson.goals = item["goals"] if item["goals"].present?
          lesson.approx_duration_min = item["approx_duration_min"].to_i if item["approx_duration_min"].present?
          save_record!(lesson)
          touch(lesson)
        end

        Array(args["lessons_to_create"]).each do |item|
          lesson = course.lessons.create!(
            title: required_string(item, "title"),
            goals: required_string(item, "goals"),
            approx_duration_min: required_integer(item, "approx_duration_min")
          )
          touch(lesson)
        end

        reorder_lessons!(course, args["lessons_order"]) if args["lessons_order"].present?
      end

      touch(course)
      { course: course.reload.for_llm }
    end

    def get_lesson(args)
      lesson = find_lesson!(args["lesson_id"])
      touch(lesson)
      lesson.for_llm
    end

    def update_lesson_plan_draft(args)
      if args["lesson_plan_status"].to_s == "published" || args["status"].to_s == "published"
        raise Error.new("External agents cannot publish lesson plans. Save draft work for teacher review.", code: "publishing_forbidden", http_status: :forbidden)
      end

      lesson = find_lesson!(args["lesson_id"])
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan(status: "draft")
      ensure_draft_lesson_plan!(lesson_plan)

      Lesson.transaction do
        lesson_plan.status = "draft"
        lesson_plan.content = normalize_lesson_plan_content(args["lesson_plan_content"]) if args.key?("lesson_plan_content")
        lesson_plan.suggested_resources = normalize_suggested_resources(args["suggested_resources"]) if args.key?("suggested_resources")
        lesson_plan.audio = args["audio"] if args.key?("audio")
        lesson_plan.chalkboard_enabled = ActiveModel::Type::Boolean.new.cast(args["chalkboard_enabled"]) if args.key?("chalkboard_enabled")
        save_record!(lesson_plan)
      end

      touch(lesson)
      touch(lesson_plan)
      { lesson: lesson_payload(lesson), lesson_plan: lesson_plan_payload(lesson_plan.reload) }
    end

    def generate_lesson_plan(args)
      lesson = find_lesson!(args["lesson_id"])
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan(status: "draft")
      ensure_draft_lesson_plan!(lesson_plan)
      lesson_plan.save! if lesson_plan.new_record?
      action = required_string(args, "action")

      case action
      when "generate_content"
        GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher, raise_on_error: true)
        touch(lesson_plan)
        { status: "completed", action: action, lesson: lesson.reload.for_llm }
      when "propose_resources_async"
        enqueue_lesson_plan_generation(lesson, lesson_plan, action) { |service| service.enqueue_propose_resources }
      when "generate_content_and_propose_resources_async"
        enqueue_lesson_plan_generation(lesson, lesson_plan, action) { |service| service.enqueue_generate_content(propose_resources: true) }
      else
        raise Error.new("Unknown action: #{action}", code: "invalid_action")
      end
    end

    def propose_lesson_resources(args)
      generate_lesson_plan(args.merge("action" => "propose_resources_async"))
    end

    def list_resources(args = {})
      scope = resource_scope.includes(:applet, file_attachment: :blob).order(created_at: :desc)
      if args["lesson_plan_id"].present?
        linked_resource_ids = find_lesson_plan!(args["lesson_plan_id"]).resources.select(:id)
        scope = scope.where(id: linked_resource_ids)
      end

      case args["approved"].to_s
      when "true"
        scope = scope.where(approved: true)
      when "false"
        scope = scope.where(approved: false)
      when "human"
        scope = scope.where(approved: nil)
      end

      scope.limit(200).map { |resource| resource_payload(resource) }
    end

    def get_resource(args)
      resource = find_resource!(args["resource_id"])
      touch(resource)
      resource_payload(resource, include_payload: true)
    end

    def create_resource(args)
      resource = nil

      Resource.transaction do
        lesson = find_lesson!(args["lesson_id"]) if args["lesson_id"].present?
        resource = Resource.new(
          teacher: teacher,
          category: args["category"].to_s.presence,
          description: required_string(args, "description"),
          include_by_default: ActiveModel::Type::Boolean.new.cast(args["include_by_default"]),
          tags: args["tags"],
          approved: ActiveModel::Type::Boolean.new.cast(args["approve"]) ? true : false
        )

        attach_resource_payload!(resource, args)
        save_record!(resource)
        link_resource_to_lesson!(resource, lesson.id) if lesson
      end

      touch(resource)
      { resource: resource_payload(resource.reload, include_payload: true) }
    end

    def update_resource(args)
      resource = find_resource!(args["resource_id"])

      Resource.transaction do
        resource.description = args["description"] if args.key?("description")
        resource.category = args["category"] if args.key?("category")
        resource.tags = args["tags"] if args.key?("tags")
        resource.include_by_default = ActiveModel::Type::Boolean.new.cast(args["include_by_default"]) if args.key?("include_by_default")

        replace_resource_payload!(resource, args) if resource_payload_update_requested?(args)
        save_record!(resource)
      end

      touch(resource)
      { resource: resource_payload(resource.reload, include_payload: true) }
    end

    def link_resource_to_lesson_plan(args)
      lesson_plan = find_lesson_plan!(args["lesson_plan_id"])
      resource = find_linkable_resource!(args["resource_id"])
      if lesson_plan.status_published? && resource.approved == false
        raise Error.new("Cannot link a pending resource to a published lesson plan.", code: "pending_resource_on_published_plan", http_status: :conflict)
      end

      lesson_plan.resources << resource unless lesson_plan.resources.exists?(id: resource.id)
      touch(lesson_plan)
      touch(resource)
      { lesson_plan: lesson_plan_payload(lesson_plan.reload), resource: resource_payload(resource) }
    end

    def unlink_resource_from_lesson_plan(args)
      lesson_plan = find_lesson_plan!(args["lesson_plan_id"])
      resource = lesson_plan.resources.merge(resource_scope_for_linking).find_by(id: args["resource_id"])
      raise Error.new("Resource not found", code: "not_found", http_status: :not_found) unless resource

      lesson_plan.resources.delete(resource)
      touch(lesson_plan)
      touch(resource)
      { lesson_plan: lesson_plan_payload(lesson_plan.reload), resource: resource_payload(resource) }
    end

    def approve_resource(args)
      resource = find_resource!(args["resource_id"])
      resource.update!(approved: true)
      touch(resource)
      { resource: resource_payload(resource.reload) }
    end

    def list_applets(_args = {})
      applet_scope.order(created_at: :desc).limit(200).map { |applet| applet_payload(applet) }
    end

    def get_applet(args)
      applet = find_applet!(args["applet_id"])
      touch(applet)
      applet_payload(applet, include_code: true)
    end

    def upsert_applet(args)
      if args["applet_id"].present?
        applet = find_applet!(args["applet_id"])
        applet.title = args["title"] if args.key?("title")
        applet.code = args["code"] if args.key?("code")
        save_record!(applet) if applet.changed?
      else
        applet = teacher.applets.new(title: required_string(args, "title"), code: required_string(args, "code"))
        save_record!(applet)
      end

      touch(applet)
      { applet: applet_payload(applet.reload, include_code: true) }
    end

    def save_applet_as_resource(args)
      applet = find_applet!(args["applet_id"])
      resource = nil

      Resource.transaction do
        resource = applet.resource || Resource.create!(
          teacher: teacher,
          category: "Applet",
          description: applet.title,
          approved: false,
          applet: applet
        )
        link_resource_to_lesson!(resource, args["lesson_id"]) if args["lesson_id"].present?
      end

      touch(applet)
      touch(resource)
      { applet: applet_payload(applet), resource: resource_payload(resource.reload) }
    end

    private

    def course_scope
      teacher.taught_courses
    end

    def student_scope
      teacher.students
    end

    def resource_scope
      Resource.where(teacher: teacher)
    end

    def resource_scope_for_linking
      Resource.where(teacher: teacher)
    end

    def applet_scope
      teacher.applets
    end

    def find_course!(id)
      course_scope.find_by(id: id).tap { |record| raise Error.new("Course not found", code: "not_found", http_status: :not_found) unless record }
    end

    def find_lesson!(id)
      Lesson.joins(:course).merge(course_scope).find_by(id: id).tap { |record| raise Error.new("Lesson not found", code: "not_found", http_status: :not_found) unless record }
    end

    def find_lesson_plan!(id)
      LessonPlan.joins(lesson: :course).merge(course_scope).find_by(id: id).tap { |record| raise Error.new("Lesson plan not found", code: "not_found", http_status: :not_found) unless record }
    end

    def find_student!(id)
      student_scope.find_by(id: id).tap { |record| raise Error.new("Student not found", code: "not_found", http_status: :not_found) unless record }
    end

    def find_resource!(id)
      resource_scope.find_by(id: id).tap { |record| raise Error.new("Resource not found", code: "not_found", http_status: :not_found) unless record }
    end

    def find_linkable_resource!(id)
      resource_scope_for_linking.find_by(id: id).tap { |record| raise Error.new("Resource not found", code: "not_found", http_status: :not_found) unless record }
    end

    def find_applet!(id)
      applet_scope.find_by(id: id).tap { |record| raise Error.new("Applet not found", code: "not_found", http_status: :not_found) unless record }
    end

    def ensure_draft_lesson_plan!(lesson_plan)
      return unless lesson_plan.persisted? && lesson_plan.status_published?

      raise Error.new(
        "External agents cannot edit published lesson plans. Move the plan back to draft before agent preparation.",
        code: "published_lesson_plan_locked",
        http_status: :forbidden
      )
    end

    def required_string(args, key)
      value = args[key].to_s.strip
      raise Error.new("Missing required argument: #{key}", code: "missing_argument", http_status: :bad_request) if value.blank?

      value
    end

    def required_integer(args, key)
      Integer(args[key])
    rescue ArgumentError, TypeError
      raise Error.new("Missing or invalid integer argument: #{key}", code: "invalid_argument", http_status: :bad_request)
    end

    def normalize_outline(items)
      Array(items).map do |item|
        topic = required_string(item, "topic")
        description = required_string(item, "description")
        { topic => description }
      end
    end

    def normalize_lesson_plan_content(items)
      Array(items).map do |item|
        type = required_string(item, "type")
        details = required_string(item, "details")
        { type => details }
      end
    end

    def normalize_suggested_resources(items)
      Array(items).map do |item|
        type = required_string(item, "type")
        description = required_string(item, "description")
        { type => description }
      end
    end

    def reorder_lessons!(course, order_items)
      order_list = Array(order_items)
      input_ids = order_list.map { |item| item["id"].to_i }.sort
      existing_ids = course.lessons.pluck(:id).sort
      unless input_ids == existing_ids
        raise Error.new("lessons_order must contain exactly all lesson IDs for this course.", code: "invalid_lesson_order")
      end

      sorted = order_list.sort_by { |item| item["position"].to_i }
      expected_positions = (1..existing_ids.count).to_a
      unless sorted.map { |item| item["position"].to_i } == expected_positions
        raise Error.new("lessons_order positions must be a contiguous sequence from 1 to N.", code: "invalid_lesson_order")
      end

      sorted.each { |item| course.lessons.find(item["id"].to_i).insert_at(item["position"].to_i) }
    end

    def enqueue_lesson_plan_generation(lesson, lesson_plan, action)
      result = yield LessonPlanAsyncGenerationService.new(lesson_plan: lesson_plan, current_user: teacher, source: "agent_api")
      raise Error.new(result[:message], code: "queue_failed") unless result[:ok]

      touch(lesson_plan)
      {
        status: "queued",
        action: action,
        message: result[:message],
        lesson_id: lesson.id,
        lesson_plan_id: lesson_plan.id,
        generation_stage: result[:stage],
        poll: { command: "get_lesson", args: { lesson_id: lesson.id } }
      }
    end

    def attach_resource_payload!(resource, args)
      payload_count = [ args["uri"].present?, args["content"].present?, args["file_base64"].present?, args["applet_attributes"].present? ].count(true)
      raise Error.new("Provide exactly one resource payload: uri, content, file_base64, or applet_attributes.", code: "invalid_resource_payload", http_status: :bad_request) unless payload_count == 1

      if args["uri"].present?
        resource.uri = args["uri"].to_s.strip
      elsif args["content"].present?
        resource.content = args["content"].to_s
      elsif args["file_base64"].present?
        attach_base64_file!(resource, args)
      elsif args["applet_attributes"].present?
        attrs = args["applet_attributes"].to_h.slice("title", "code")
        resource.category ||= "Applet"
        resource.build_applet(title: attrs["title"], code: attrs["code"], user: teacher)
      end
    end

    def attach_base64_file!(resource, args)
      filename = required_string(args, "filename")
      content_type = required_string(args, "content_type")
      decoded = Base64.strict_decode64(args["file_base64"].to_s)
      resource.file.attach(io: StringIO.new(decoded), filename: filename, content_type: content_type)
    rescue ArgumentError
      raise Error.new("file_base64 must be valid strict Base64.", code: "invalid_file_base64", http_status: :bad_request)
    end

    def resource_payload_update_requested?(args)
      args["uri"].present? || args["content"].present? || args["file_base64"].present?
    end

    def replace_resource_payload!(resource, args)
      payload_count = [ args["uri"].present?, args["content"].present?, args["file_base64"].present? ].count(true)
      raise Error.new("Provide only one replacement payload: uri, content, or file_base64.", code: "invalid_resource_payload", http_status: :bad_request) unless payload_count == 1
      raise Error.new("Applet resource payloads cannot be replaced through update_resource.", code: "applet_payload_replace_forbidden", http_status: :conflict) if resource.applet.present?

      resource.file.detach if resource.file.attached?
      resource.uri = nil
      resource.content = nil

      if args["uri"].present?
        resource.uri = args["uri"].to_s.strip
      elsif args["content"].present?
        resource.content = args["content"].to_s
      elsif args["file_base64"].present?
        attach_base64_file!(resource, args)
      end
    end

    def link_resource_to_lesson!(resource, lesson_id)
      lesson = find_lesson!(lesson_id)
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan(status: "draft")
      lesson_plan.save! if lesson_plan.new_record?
      if lesson_plan.status_published? && resource.approved == false
        raise Error.new("Cannot link a pending resource to a published lesson plan.", code: "pending_resource_on_published_plan", http_status: :conflict)
      end

      lesson_plan.resources << resource unless lesson_plan.resources.exists?(id: resource.id)
      touch(lesson_plan)
    end

    def save_record!(record)
      return if record.save

      raise Error.new("Validation failed: #{record.errors.full_messages.join(', ')}", code: "validation_failed")
    rescue ActiveRecord::RecordInvalid => e
      raise Error.new("Validation failed: #{e.record.errors.full_messages.join(', ')}", code: "validation_failed")
    end

    def touch(record)
      key = record.class.name.underscore.pluralize
      @touched_records[key] << record.id
      @touched_records[key].uniq!
    end

    def user_payload(user)
      { id: user.id, name: user.name, email: user.email, role: user.role }
    end

    def course_summary(course)
      {
        id: course.id,
        title: course.title,
        summary: course.summary,
        grade_level: course.grade_level,
        status: course.status,
        lesson_count: course.lessons.count,
        created_at: course.created_at,
        updated_at: course.updated_at
      }
    end

    def lesson_payload(lesson)
      { id: lesson.id, title: lesson.title, goals: lesson.goals, approx_duration_min: lesson.approx_duration_min, course_id: lesson.course_id, position: lesson.position }
    end

    def lesson_plan_payload(lesson_plan)
      {
        id: lesson_plan.id,
        lesson_id: lesson_plan.lesson_id,
        status: lesson_plan.status,
        generation_stage: lesson_plan.generation_stage,
        generation_error: lesson_plan.generation_error,
        content: lesson_plan.content,
        suggested_resources: lesson_plan.suggested_resources,
        resource_ids: lesson_plan.resources.pluck(:id),
        audio: lesson_plan.audio,
        chalkboard_enabled: lesson_plan.chalkboard_enabled
      }
    end

    def resource_payload(resource, include_payload: false)
      payload = {
        id: resource.id,
        category: resource.category,
        description: resource.description,
        approved: resource.approved,
        include_by_default: resource.include_by_default,
        tags: resource.tags,
        uri: resource.uri,
        has_content: resource.content.present?,
        file_attached: resource.file.attached?,
        filename: resource.file.attached? ? resource.file.filename.to_s : nil,
        content_type: resource.file.attached? ? resource.file.content_type : nil,
        applet_id: resource.applet&.id,
        created_at: resource.created_at,
        updated_at: resource.updated_at
      }
      payload[:content] = resource.content if include_payload && resource.content.present?
      payload
    end

    def applet_payload(applet, include_code: false)
      payload = { id: applet.id, title: applet.title, resource_id: applet.resource_id, created_at: applet.created_at, updated_at: applet.updated_at }
      payload[:code] = applet.code if include_code
      payload
    end

    def build_student_profile(student, focus:)
      today_str = Time.current.strftime("%B %d, %Y")
      journal_link = Rails.application.routes.url_helpers.admin_student_path(student, active_tab: "journal_timeline")
      pending_observation_count = student.observations.pending.count
      lesson_reports = student.student_reports.lesson_reports.status_completed.where(teacher: teacher).order(created_at: :desc).limit(6)
      course_reports = student.student_reports.course_reports.status_completed.where(teacher: teacher).order(created_at: :desc).limit(3)
      profile_report = student.student_reports.profile_reports.status_completed.where(teacher: teacher).order(created_at: :desc).first
      memories_recent = student.memories.order(created_at: :desc).limit(8)
      observations_recent = student.observations.for_context.limit(12)
      feedback_recent = student.student_feedbacks.includes(:lesson_progress).order(created_at: :desc).limit(5)
      enrollments_in_progress = student.enrollments.in_progress.includes(:course).order(created_at: :desc)
      focus_memories, focus_observations, focus_mode = focus_context(student, focus, memories_recent, observations_recent)
      last_message_at = Message.joins(:conversation).where(conversations: { user_id: student.id }).order(created_at: :desc).limit(1).pluck(:created_at).first
      last_activity_at = [ last_message_at, lesson_reports.first&.created_at, course_reports.first&.created_at, feedback_recent.first&.created_at ].compact.max

      ApplicationController.render(
        partial: "students/student_profile",
        formats: [ :md ],
        locals: {
          student: student,
          teacher: teacher,
          today_str: today_str,
          journal_link: journal_link,
          pending_observation_count: pending_observation_count,
          enrollments_in_progress: enrollments_in_progress,
          lesson_reports: lesson_reports,
          course_reports: course_reports,
          profile_report: profile_report,
          memories_recent: memories_recent,
          observations_recent: observations_recent,
          feedback_recent: feedback_recent,
          focus: focus,
          focus_mode: focus_mode,
          focus_memories: focus_memories,
          focus_observations: focus_observations,
          last_activity_at: last_activity_at
        }
      ).to_s
    end

    def focus_context(student, focus, memories_recent, observations_recent)
      return [ [], [], nil ] if focus.blank?

      focus_mode = "keyword"
      focus_memories = []
      focus_observations = []

      if AppSetting.embeddings_configured?
        vector = EmbeddingService.get(focus)
        if vector
          focus_mode = "embeddings"
          focus_memories = Memory.nearest_neighbors(:embedding, vector, distance: "cosine").where(student: student).limit(5)
          focus_observations = Observation.nearest_neighbors(:embedding, vector, distance: "cosine").where(student: student).approved.limit(5)
        end
      end

      if focus_mode == "keyword"
        q = focus.downcase
        focus_memories = memories_recent.select { |memory| memory.body.to_s.downcase.include?(q) }.first(5)
        focus_observations = observations_recent.select { |observation| observation.content.to_s.downcase.include?(q) }.first(5)
      end

      recent_memory_ids = memories_recent.map(&:id).to_set
      recent_observation_ids = observations_recent.map(&:id).to_set
      [
        focus_memories.uniq { |memory| memory.id }.reject { |memory| recent_memory_ids.include?(memory.id) },
        focus_observations.uniq { |observation| observation.id }.reject { |observation| recent_observation_ids.include?(observation.id) },
        focus_mode
      ]
    rescue StandardError => e
      Rails.logger.warn("Agent API focus retrieval failed: #{e.message}")
      [ [], [], "keyword" ]
    end
  end
end
