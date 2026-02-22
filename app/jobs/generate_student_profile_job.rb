class GenerateStudentProfileJob < ApplicationJob
  queue_as :default

  PROFILE_SCHEMA = {
    strict: true,
    name: "Student_Profile",
    description: "A synthesized profile of the student's current learning state and patterns.",
    schema: LlmSchemas::StudentProfileSchema.to_json_schema.deep_stringify_keys
  }

  PROFILE_KEY_ORDER = Array(PROFILE_SCHEMA.dig(:schema, "required")).map(&:to_s).freeze

  def perform(student)
    teacher = student.teacher
    return unless teacher # Orphaned students cannot generate profiles

    task_prompt = Prompt.get_prompt(category: "generate_student_profile", user: teacher)

    # Gather data sources
    recent_lesson_reports = format_lesson_reports(student)
    course_reports = format_course_reports(student)
    observations = format_observations(student)
    memories = format_memories(student)
    student_feedback = format_student_feedback(student)
    previous_profile = student.student_reports.profile_reports.status_completed.order(created_at: :desc).first
    previous_profile_date = previous_profile&.created_at&.strftime("%B %d, %Y")

    customized_prompt = task_prompt
      .gsub("{student_name}", student.name)
      .gsub("{current_date}", Time.current.strftime("%B %d, %Y"))
      .gsub("{previous_profile_date}", previous_profile_date || "None")
      .gsub("{recent_lesson_reports}", recent_lesson_reports.presence || "No lesson reports available.")
      .gsub("{course_reports}", course_reports.presence || "No course reports available.")
      .gsub("{observations}", observations.presence || "No observations available.")
      .gsub("{memories}", memories.presence || "No memories recorded.")
      .gsub("{student_feedback}", student_feedback.presence || "No student feedback available.")

    messages = [ { role: "user", content: customized_prompt } ]

    begin
      client = OpenaiApiService.new(
        current_user: teacher,
        reasoning_model: true
      )
      parsed_content = client.complete(
        messages,
        response_format: {
          type: "json_schema",
          json_schema: PROFILE_SCHEMA.slice(:name, :schema, :strict)
        },
        schema: PROFILE_SCHEMA[:schema],
        prefill: "{"
      )

      # Create the student profile report
      report = StudentReport.create!(
        student: student,
        teacher: teacher,
        reportable: student, # reportable_type: "User"
        progress_data: parsed_content,
        author_type: :ai_generated,
        status: :completed
      )

      Rails.logger.info "Student profile generated for student: #{student.id}"

      link = Rails.application.routes.url_helpers.admin_student_path(
        student,
        active_tab: "journal",
        anchor: "student_report_#{report.id}"
      )
      current_snapshot = parsed_content.is_a?(Hash) ? parsed_content["current_snapshot"].to_s.squish.truncate(2000) : ""

      Rails.event.notify(Events::StudentProfileGenerated.new(
        recipient_ids: teacher.id,
        link: link,
        student_name: student.name,
        current_snapshot: current_snapshot,
        report_id: report.id
      ))

    rescue StandardError => e
      Rails.logger.error "Error generating student profile for student #{student.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
    end
  end

  private

  def format_lesson_reports(student)
    # Get recent lesson reports (last 20, most recent first)
    reports = student.student_reports
                     .lesson_reports
                     .where.not(progress_data: nil)
                     .order(created_at: :desc)
                     .limit(20)

    reports.map do |report|
      lesson = report.reportable&.lesson
      course = lesson&.course
      <<~REPORT
        [#{report.created_at.strftime("%B %d, %Y")}] #{course&.title || "Unknown Course"} - #{lesson&.title || "Unknown Lesson"}
        #{report.to_markdown}
      REPORT
    end.join("\n---\n")
  end

  def format_course_reports(student)
    reports = student.student_reports
                     .course_reports
                     .where.not(progress_data: nil)
                     .order(created_at: :desc)
                     .limit(5)

    reports.map do |report|
      course = report.reportable&.course
      <<~REPORT
        [#{report.created_at.strftime("%B %d, %Y")}] Course Completed: #{course&.title || "Unknown Course"}
        #{report.to_markdown}
      REPORT
    end.join("\n---\n")
  end

  def format_observations(student)
    observations = student.observations
                          .for_context
                          .limit(30)

    observations.map do |obs|
      weight_percent = (obs.effective_weight.to_f * 100).round
      "- [#{obs.created_at.strftime("%B %d, %Y")}] (weight: #{weight_percent}%) #{obs.content}"
    end.join("\n")
  end

  def format_memories(student)
    student.memories.map do |memory|
      visibility = memory.hidden_from_student? ? " [hidden from student]" : ""
      "- #{memory.body}#{visibility}"
    end.join("\n")
  end

  def format_student_feedback(student)
    feedbacks = student.student_feedbacks
                       .order(created_at: :desc)
                       .limit(30)

    feedbacks.map do |feedback|
      lesson_context = if feedback.lesson_progress&.lesson
        " (during #{feedback.lesson_progress.lesson.title})"
      else
        ""
      end
      "- [#{feedback.created_at.strftime("%B %d, %Y")}]#{lesson_context} #{feedback.content}"
    end.join("\n")
  end
end
