class ResponsesNativeTranscript
  OPAQUE_REASONING_KEYS = %w[encrypted_content signature data content].freeze

  def initialize(initial_input_items:)
    if initial_input_items.blank?
      raise OpenAiError, "Responses API did not expose the resolved input needed for stateless replay."
    end

    @input_items = deep_dup(initial_input_items)
    @latest_output_items = []
  end

  def input_items
    deep_dup(@input_items)
  end

  def append_response!(response_hash, omit_reasoning: false)
    @latest_output_items = deep_dup(Array(response_hash["output"]))
    if omit_reasoning
      @latest_output_items.reject! { |item| item["type"].to_s.include?("reasoning") }
    end
    @input_items.concat(@latest_output_items)
    self
  end

  def append_function_call_outputs!(outputs)
    pending_calls = @latest_output_items.select { |item| item["type"].to_s == "function_call" }
    pending_ids = pending_calls.map { |call| call["call_id"].to_s }
    raise OpenAiError, "No pending function calls are available for these tool outputs." if pending_ids.empty?
    raise OpenAiError, "A pending function call is missing call_id." if pending_ids.any?(&:blank?)
    raise OpenAiError, "Duplicate pending function call IDs were returned." if pending_ids.uniq.size != pending_ids.size

    outputs_by_call_id = Array(outputs).each_with_object({}) do |output, memo|
      call_id = value(output, :call_id).to_s
      raise OpenAiError, "A function call output is missing call_id." if call_id.blank?
      raise OpenAiError, "Duplicate function call output for call_id #{call_id}." if memo.key?(call_id)

      memo[call_id] = output
    end

    missing_ids = pending_ids - outputs_by_call_id.keys
    unknown_ids = outputs_by_call_id.keys - pending_ids
    if missing_ids.present? || unknown_ids.present?
      raise OpenAiError,
            "Function call outputs must cover every pending call exactly once. " \
            "missing=#{missing_ids.join(',').presence || 'none'} unknown=#{unknown_ids.join(',').presence || 'none'}"
    end

    @input_items.concat(pending_ids.map { |call_id| deep_dup(outputs_by_call_id.fetch(call_id)) })
    self
  end

  def append_user_message!(content)
    text = content.to_s
    raise OpenAiError, "A stateless follow-up message cannot be blank." if text.blank?

    @input_items << { role: "user", content: text }
    self
  end

  def reasoning_replayable_for_tool_boundary?(response_hash)
    return true if function_calls(response_hash).blank?

    reasoning_items = Array(response_hash["output"]).select do |item|
      item["type"].to_s.include?("reasoning")
    end
    return reasoning_tokens(response_hash).zero? if reasoning_items.empty?

    reasoning_items.all? do |item|
      OPAQUE_REASONING_KEYS.any? { |key| item[key].present? }
    end
  end

  private

  def function_calls(response_hash)
    Array(response_hash["output"]).select { |item| item["type"].to_s == "function_call" }
  end

  def reasoning_tokens(response_hash)
    usage = response_hash["usage"] || {}
    (
      usage.dig("output_tokens_details", "reasoning_tokens") ||
      usage.dig("completion_tokens_details", "reasoning_tokens")
    ).to_i
  end

  def value(hash, key)
    return nil unless hash.is_a?(Hash)

    hash[key] || hash[key.to_s]
  end

  def deep_dup(value)
    value.respond_to?(:deep_dup) ? value.deep_dup : value
  end
end
