class CourseOutlineResearchBroadcasts
  class << self
    include ActionView::RecordIdentifier

    def broadcast_editor_state(course:, current_user:)
      return if course.blank? || current_user.blank?

      channel = "teacher_#{current_user.id}-dashboard"

      Turbo::StreamsChannel.broadcast_replace_to(
        channel,
        target: dom_id(course),
        partial: "admin/courses/course",
        locals: { course: course, current_user: current_user }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        channel,
        target: dom_id(course, :outline_research_panel),
        partial: "admin/courses/outline_research_panel_container",
        locals: { course: course }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        channel,
        target: dom_id(course, :outline_research_progress),
        partial: "admin/courses/outline_research_progress",
        locals: { course: course }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        channel,
        target: dom_id(course, :form),
        partial: "admin/courses/form",
        locals: { course: course }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        channel,
        target: dom_id(course, :outline_research_snapshot),
        partial: "admin/courses/outline_research_snapshot_container",
        locals: { course: course }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        channel,
        target: dom_id(course, :outline_research_lock_state),
        partial: "admin/courses/outline_research_lock_state",
        locals: { course: course }
      )
    end
  end
end
