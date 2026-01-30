class JournalService
  def self.get_timeline(student, teacher_mode: false, page: 1, per_page: 15)
    offset = (page - 1) * per_page

    # 1. Build sub-queries using Active Record
    # We select only the necessary columns for the Union

    obs_scope = teacher_mode ? student.observations.where.not(status: :pending) : student.observations.approved
    observations_sql = obs_scope.select("id, 'Observation' as record_type, created_at").to_sql

    feedbacks_sql = student.student_feedbacks.select("id, 'StudentFeedback' as record_type, created_at").to_sql

    reports_sql = student.student_reports.select("id, 'StudentReport' as record_type, created_at").to_sql

    memories_sql = student.memories.select("id, 'Memory' as record_type, created_at").to_sql

    # 2. Construct the final Union query
    # We wrap the union in a subquery to allow global ordering and pagination
    sql = <<~SQL
      SELECT * FROM (
        #{observations_sql}
        UNION ALL
        #{feedbacks_sql}
        UNION ALL
        #{reports_sql}
        UNION ALL
        #{memories_sql}
      ) AS timeline_items
      ORDER BY created_at DESC
      LIMIT $1 OFFSET $2
    SQL

    # 3. Execute
    results = ActiveRecord::Base.connection.select_all(sql, nil, [ per_page, offset ])

    # 4. Load Records
    ids_by_type = results.each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, hash|
      hash[row["record_type"]] << row["id"]
    end

    loaded_records = []
    ids_by_type.each do |type, ids|
      klass = type.constantize
      query = klass.where(id: ids)

      case type
      when "Observation"
        query = query.includes(:author)
      when "StudentReport"
        query = query.includes(:teacher)
      when "Memory"
        query = query.includes(:author)
      end

      loaded_records.concat(query.to_a)
    end

    # 5. Re-sort
    loaded_records.sort_by(&:created_at).reverse
  end
end
