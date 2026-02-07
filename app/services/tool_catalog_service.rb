class ToolCatalogService
  def initialize(user:, conversation: nil, base_uri: nil)
    @user = user
    @conversation = conversation
    @base_uri = base_uri.to_s
  end

  def allowed_tools
    @allowed_tools ||= begin
      scoped = Tool.enabled_for_user(@user)
      scoped = scoped.where(access: :student) if @conversation&.lesson_progress.present?

      tools = scoped.to_a
      if @conversation&.lesson_progress.blank? && @user.role_teacher?
        tools.reject! { |tool| tool.name == "View_Applets" }
      end
      tools
    end
  end

  def for_chat_completions
    allowed_tools
      .map(&:for_llm)
      .reject { |tool| tool.dig("function", "name") == "Generate_Image" && !openrouter_provider? }
  end

  def for_responses
    allowed_tools
      .map { |tool| format_response_tool(tool) }
      .reject { |tool| tool["name"] == "Generate_Image" && !openrouter_provider? }
  end

  private

  def openrouter_provider?
    @base_uri.include?("openrouter.ai")
  end

  def format_response_tool(tool)
    spec = tool.specifications
    {
      "type" => "function",
      "name" => spec["name"] || spec[:name],
      "description" => spec["description"] || spec[:description],
      "parameters" => spec["parameters"] || spec[:parameters],
      "strict" => spec["strict_mode"] || spec[:strict_mode]
    }.compact
  end
end
