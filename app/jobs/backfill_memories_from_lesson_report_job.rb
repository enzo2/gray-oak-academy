class BackfillMemoriesFromLessonReportJob < ApplicationJob
  queue_as :default

  MERGED_MEMORIES_SCHEMA = {
    "name": "Merged_Memories",
    "description": "An object containing consolidated new memories and IDs of existing memories to replace",
    "schema": {
      "type": "object",
      "properties": {
        "new_memories": {
          "type": "array",
          "items": { "type": "string" }
        },
        "replacement_ids": {
          "type": "array",
          "items": { "type": "integer" }
        }
      },
      "required": [ "new_memories" ],
      "additionalProperties": false
    }
  }

  def perform(student_report)
    # Validate input
    return unless valid_report?(student_report)

    # Preparations
    student = student_report.student

    new_memories_text = normalize_candidate_memories(student_report.progress_data&.dig("memories"))
    return if new_memories_text.empty?

    existing_memories = existing_memories_for(student, new_memories_text)

    task_system_prompt = Prompt.get_prompt(category: "memories_semantic_merge", user: student)

    message_prompt = <<~PROMPT
      Existing memories:#{' '}
      #{existing_memories.to_json}

      New candidate memories:#{' '}
      #{new_memories_text.to_json}
    PROMPT

    messages = [ { role: "user", content: message_prompt } ]

    # Call LLM and process response
    begin
      client = OpenaiApiService.new(
        current_user: student,
        task_system_prompt: task_system_prompt,
        reasoning_model: true
      )

      parsed_content = client.complete(
        messages,
        response_format: {
          type: "json_schema",
          json_schema: MERGED_MEMORIES_SCHEMA[:schema]
        },
        schema: MERGED_MEMORIES_SCHEMA[:schema],
        prefill: "{\"new_memories\": ["
      )

      unless parsed_content.is_a?(Hash) && parsed_content["new_memories"].is_a?(Array)
        raise "Invalid response format from LLM"
      end

      new_memories = parsed_content["new_memories"]
      replacement_ids = parsed_content["replacement_ids"]

      Rails.logger.debug "Consolidated memories for student #{student.id} from report #{student_report.id}: #{new_memories}"

      # Add and delete memories in a single transaction
      ActiveRecord::Base.transaction do
        new_memories.each do |memory_body|
          body = memory_body.to_s.strip
          next if body.blank?
          Memory.create!(
            student: student,
            student_report: student_report,
            body: body,
            hidden_from_student: false # Students can see and manage all LLM-generated memories.
          )
          Rails.logger.debug "Created memory for student #{student.id} from report #{student_report.id}: #{body}"
        end

        # Only delete memories belonging to this student.
        student.memories.where(id: replacement_ids).delete_all if replacement_ids.is_a?(Array) && replacement_ids.any?
      end
    rescue StandardError => e
      Rails.logger.error "Error consolidating memories for student #{student.id} from report #{student_report.id}: #{e.class}: #{e.message}"
    end
  end

  private

  def valid_report?(student_report)
    return false unless student_report.is_a?(StudentReport)
    return false unless student_report.reportable_type == "LessonProgress"
    return false unless student_report.student
    return false unless student_report.progress_data.is_a?(Hash)

    memories_data = student_report.progress_data["memories"]
    memories_data.is_a?(Array) && memories_data.any?
  end

  def existing_memories_for(student, new_memories_text = [])
    if AppSetting.embeddings_configured?
      relevant_ids = Set.new

      new_memories_text.each do |memory_text|
        vector = EmbeddingService.get(memory_text)
        next unless vector

        # Find top matches for this specific memory
        neighbor_records = Memory.nearest_neighbors(:embedding, vector, distance: "cosine")
                                 .where(student: student).limit(5)
        Rails.logger.debug "Found neighbor memories with similarities #{neighbor_records.map(&:neighbor_distance).join(', ')} for new memory: #{memory_text.truncate(50)}"
        relevant_ids.merge(neighbor_records.map(&:id))
      end

      base_query = relevant_ids.empty? ? student.memories : student.memories.where(id: relevant_ids)
    else # embeddings not configured
      base_query = student.memories
    end

    base_query.pluck(:id, :body).map { |id, body| { id: id, body: body } }
  end

  def normalize_candidate_memories(memories_data)
    return [] unless memories_data.is_a?(Array)

    memories_data.flat_map do |memory_data|
      body =
        case memory_data
        when Hash
          memory_data["body"]
        when String
          memory_data
        end

      body = body.to_s.strip
      body.present? ? [ body ] : []
    end.uniq
  end
end
