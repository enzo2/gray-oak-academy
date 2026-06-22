class ResponsesAgentLoop
  MAX_DURATION_SECONDS = 30.minutes.to_i
  REQUEST_TIMEOUT_SECONDS = 900
  CONTEXT_LIMIT_RATIO = 0.8

  attr_reader :current_response, :reasoning_fallback_used

  def initialize(client:, clock: nil)
    @client = client
    @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    @started_at = @clock.call
    @reasoning = { effort: "high" }
    @reasoning_fallback_used = false
    @context_warning_logged = false
  end

  def start(messages:, metadata:)
    @initial_messages = deep_dup(messages)
    response_hash = submit(messages: @initial_messages, metadata: metadata)
    transcript = transcript_from_last_request

    if !transcript.reasoning_replayable_for_tool_boundary?(response_hash)
      log_reasoning_fallback!(metadata: metadata, response_hash: response_hash)
      @reasoning = { effort: "none" }
      @reasoning_fallback_used = true
      response_hash = submit(
        messages: @initial_messages,
        metadata: fallback_metadata(metadata)
      )
      transcript = transcript_from_last_request
    end

    append_response_for_replay!(transcript, response_hash)
    @transcript = transcript
    @current_response = response_hash
  end

  def continue_with_tool_outputs(outputs:, metadata:)
    ensure_started!
    guard_continuation!
    @transcript.append_function_call_outputs!(outputs)
    continue_with_input(metadata: metadata)
  end

  def continue_with_user_message(content:, metadata:)
    ensure_started!
    guard_continuation!
    @transcript.append_user_message!(content)
    continue_with_input(metadata: metadata)
  end

  private

  def continue_with_input(metadata:)
    response_hash = submit(input: @transcript.input_items, metadata: metadata)
    unless @reasoning[:effort] == "none" || @transcript.reasoning_replayable_for_tool_boundary?(response_hash)
      raise OpenAiError,
            "Stateless Responses reasoning became unreplayable after tools had executed; refusing an unsafe restart."
    end

    append_response_for_replay!(@transcript, response_hash)
    @current_response = response_hash
  end

  def append_response_for_replay!(transcript, response_hash)
    omit_reasoning = @reasoning[:effort] == "none" &&
      !transcript.reasoning_replayable_for_tool_boundary?(response_hash)
    if omit_reasoning
      Rails.logger.warn(
        "Provider returned unreplayable reasoning after reasoning was disabled; omitting reasoning items from stateless replay."
      )
    end
    transcript.append_response!(response_hash, omit_reasoning: omit_reasoning)
  end

  def submit(messages: nil, input: nil, metadata:)
    remaining = remaining_seconds
    raise OpenAiError, "Stateless agent run exceeded the 30-minute execution limit." if remaining <= 0

    submitted = @client.complete(
      messages,
      input: input,
      background: true,
      metadata: metadata,
      reasoning: @reasoning,
      request_timeout_seconds: [ remaining, REQUEST_TIMEOUT_SECONDS ].min
    )
    response_id = submitted["id"].to_s
    raise OpenAiError, "Responses API did not return a response id for agent execution." if response_id.blank?

    response_hash = @client.wait_for_response(
      response_id,
      timeout_seconds: [ remaining_seconds.ceil, REQUEST_TIMEOUT_SECONDS ].min.clamp(1, REQUEST_TIMEOUT_SECONDS),
      poll_interval_seconds: 2
    )
    raise OpenAiError, "Responses API did not return a valid response payload." if response_hash.blank?

    status = response_hash["status"].to_s
    if status != "completed"
      error = response_hash.dig("error", "message").presence || response_hash["error"].to_s.presence || "Unknown error"
      raise OpenAiError, "Responses agent turn failed with status '#{status}': #{error}"
    end

    response_hash
  end

  def guard_continuation!
    raise OpenAiError, "Stateless agent run exceeded the 30-minute execution limit." if remaining_seconds <= 0

    input_tokens = response_input_tokens(@current_response)
    context_length = model_context_length
    if context_length.blank?
      unless @context_warning_logged
        Rails.logger.warn(
          "No context length metadata is available for stateless agent model #{@client.model} at #{@client.base_uri}; " \
          "skipping the 80% context guard."
        )
        @context_warning_logged = true
      end
      return
    end

    return if input_tokens < (context_length * CONTEXT_LIMIT_RATIO)

    raise OpenAiError,
          "Stateless agent run reached the context safety limit " \
          "(#{input_tokens} reported input tokens / #{context_length} context tokens)."
  end

  def response_input_tokens(response_hash)
    usage = response_hash.to_h["usage"] || {}
    (usage["input_tokens"] || usage["prompt_tokens"]).to_i
  end

  def model_context_length
    return @model_context_length if defined?(@model_context_length)

    context_length = Llm.find_by(
      api_provider: SupportedApi.normalize_base_uri(@client.base_uri),
      model: @client.model
    )&.context_length.to_i
    @model_context_length = context_length.positive? ? context_length : nil
  end

  def transcript_from_last_request
    ResponsesNativeTranscript.new(initial_input_items: @client.last_input_items)
  end

  def log_reasoning_fallback!(metadata:, response_hash:)
    Rails.logger.warn(
      "Stateless Responses reasoning fallback used " \
      "run_id=#{metadata_value(metadata, :run_id) || 'none'} " \
      "provider=#{client_value(:base_uri) || 'unknown'} " \
      "model=#{client_value(:model) || 'unknown'} " \
      "response_id=#{response_hash['id']} reason=unreplayable_reasoning"
    )
  end

  def metadata_value(metadata, key)
    return nil unless metadata.is_a?(Hash)

    metadata[key] || metadata[key.to_s]
  end

  def client_value(method_name)
    @client.public_send(method_name) if @client.respond_to?(method_name)
  end

  def fallback_metadata(metadata)
    metadata.to_h.merge(phase: "reasoning_fallback", retry_reason: "unreplayable_reasoning")
  end

  def remaining_seconds
    MAX_DURATION_SECONDS - (@clock.call - @started_at)
  end

  def ensure_started!
    raise OpenAiError, "Stateless agent loop has not been started." unless @transcript
  end

  def deep_dup(value)
    value.respond_to?(:deep_dup) ? value.deep_dup : value
  end
end
