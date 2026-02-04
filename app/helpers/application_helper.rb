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
end
