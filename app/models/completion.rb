# For storing token usage and cost data.
class Completion < ApplicationRecord
  belongs_to :llm
  belongs_to :conversation, optional: true
  before_validation :associate_llm # Set the LLM association automatically.
  self.implicit_order_column = "created_at"

  validates :model, presence: true

  # For querying token usage and cost data
  def self.usage_data_query(relation = self)
    relation
      .joins(:llm)
      .group("llms.id") # Single GROUP BY on the LLM ID is sufficient thanks to the unique index
      .select(
        "llms.model",
        "llms.api_provider",
        "llms.context_length",
        "llms.model_provider",
        "llms.supports_tool_use",
        "llms.supports_structured_outputs",
        "llms.supports_image_input",
        "llms.supports_image_output",
        "llms.supports_audio_input",
        "llms.supports_audio_output",
        "llms.supports_streaming_audio",
        "SUM(prompt_tokens) AS total_prompt_tokens",
        "SUM(cached_tokens) AS total_cached_tokens",
        "SUM(completion_tokens) AS total_completion_tokens",
        "SUM(total_tokens) AS total_tokens",
        "SUM(total_cost) AS total_cost"
      )
  end

  # For querying token usage and cost data for all time
  def self.all_time_usage_data
    usage_data_query
  end

  # For querying token usage and cost data within a date range
  def self.date_ranged_usage_data(start_date, end_date)
    usage_data_query(
      where(created_at: start_date.beginning_of_day..end_date.end_of_day)
    )
  end

  private

  def associate_llm
    Rails.logger.info "Associating LLM for completion: #{self.inspect}"
    self.llm = Llm.find_or_create_by!(
      model: model,
      api_provider: api_provider
    )
  end
end
