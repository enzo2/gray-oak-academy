class ToolCatalogService
  def initialize(user:, conversation: nil)
    @user = user
    @conversation = conversation
  end

  def allowed_tools
    @allowed_tools ||= begin
      scoped = Tool.enabled_for_user(@user)
      scoped = scoped.where(access: :student) if @conversation&.lesson_progress.present?

      tools = scoped.to_a
      if @conversation&.lesson_progress.blank? && @user.role_teacher?
        tools.reject! { |tool| tool.name == "View_Applets" }
      end
      unless AppSetting.exa_enabled?
        tools.reject! { |tool| tool.name == "Web" }
      end
      tools
    end
  end

  def for_chat_completions
    allowed_tools
      .map(&:for_llm)
  end

  def for_responses
    allowed_tools
      .map { |tool| format_response_tool(tool) }
  end

  private

  def format_response_tool(tool)
    spec = tool.specifications
    {
      "type" => "function",
      "name" => spec["name"] || spec[:name],
      "description" => spec["description"] || spec[:description],
      "parameters" => spec["parameters"] || spec[:parameters],
      "strict" => strict_mode(spec)
    }
  end

  def strict_mode(spec)
    raw = spec["strict_mode"]
    raw = spec[:strict_mode] if raw.nil?
    return false if raw.nil?

    ActiveModel::Type::Boolean.new.cast(raw)
  end
end
