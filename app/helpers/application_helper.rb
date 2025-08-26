module ApplicationHelper
  include ActiveSupport::NumberHelper

  def friendly_tool_name(tool_name)
    tool_name.gsub(/[_-]/, " ")
  end
end
