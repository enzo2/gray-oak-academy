# Shared filtering for Responses API `function_call` output items.
#
# OpenRouter occasionally emits malformed `chatcmpl-tool-*` artifacts with a
# blank name (and sometimes a blank call_id). Replaying those items breaks
# stateless multi-turn tool calls, so callers must drop them before executing
# tools or rebuilding a transcript for replay.
module ResponsesFunctionCalls
  private

  def function_call_item?(item)
    item.is_a?(Hash) && item["type"].to_s == "function_call"
  end

  def valid_function_call?(item)
    function_call_item?(item) &&
      item["call_id"].to_s.present? &&
      item["name"].to_s.present?
  end

  # Returns the valid function_call items from a Responses payload, logging a
  # single warning when malformed function_call items are dropped.
  def select_valid_function_calls(response_hash, log_label:)
    candidates = Array(response_hash["output"]).select { |item| function_call_item?(item) }
    valid_calls, malformed_calls = candidates.partition { |item| valid_function_call?(item) }
    if malformed_calls.present?
      Rails.logger.warn(
        "#{log_label} ignored #{malformed_calls.size} malformed function_call item(s) " \
        "response_id=#{response_hash['id'].to_s.presence || 'unknown'}"
      )
    end
    valid_calls
  end
end
