class JournalService
  def self.get_timeline(student, teacher_mode: false, page: 1, per_page: 15)
    observations = teacher_mode ? student.observations : student.observations.approved
    observations = observations.includes(:author)

    feedbacks = student.student_feedbacks
    reports = student.student_reports.includes(:teacher)
    memories = student.memories.includes(:author)

    # In-memory merge and sort.
    # For MVP this is acceptable. For scale, we would need SQL Union or specialized pagination.

    items = []
    items.concat(observations)
    items.concat(feedbacks)
    items.concat(reports)
    items.concat(memories)

    sorted_items = items.sort_by(&:created_at).reverse

    # Pagination
    start_index = (page - 1) * per_page
    sorted_items.slice(start_index, per_page) || []
  end
end
