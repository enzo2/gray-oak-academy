module ApplicationHelper
  include ActiveSupport::NumberHelper

  def friendly_tool_name(tool_name)
    tool_name.gsub(/[_-]/, " ")
  end

  # .blank? doesn't handle zero-width characters like ZWSP, so we need to remove them first.
  def effectively_blank_text?(text)
    text.to_s.gsub(/\p{Cf}/, "").blank?
  end

  def effectively_present_text?(text)
    !effectively_blank_text?(text)
  end

  def reasoning_summary_lines(reasoning_details)
    Array(reasoning_details).flat_map do |detail|
      summary = if detail.is_a?(Hash)
        detail["summary"] || detail[:summary]
      end
      extract_reasoning_summary_lines(summary)
    end.filter_map do |line|
      text = line.to_s.strip
      text if text.present?
    end
  end

  def extract_reasoning_summary_lines(summary)
    case summary
    when String
      [ summary ]
    when Array
      summary.flat_map { |entry| extract_reasoning_summary_lines(entry) }
    when Hash
      text = summary["text"] || summary[:text] || summary["summary_text"] || summary[:summary_text]
      text.present? ? [ text ] : []
    else
      []
    end
  end
end
