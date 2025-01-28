# For storing token usage and cost data.
class Completion < ApplicationRecord
  validates :model, presence: true

  def self.all_time_usage_data
    group(:model, :api_provider)
    .select(
      :model,
      :api_provider,
      "SUM(prompt_tokens) AS total_prompt_tokens",
      "SUM(cached_tokens) AS total_cached_tokens",
      "SUM(completion_tokens) AS total_completion_tokens",
      "SUM(total_tokens) AS total_tokens",
      "SUM(total_cost) AS total_costs"
    )
  end

  def self.date_ranged_usage_data(start_date, end_date)
    where(created_at: start_date.beginning_of_day..end_date.end_of_day)
    .group(:model, :api_provider)
    .select(
      :model,
      :api_provider,
      "SUM(prompt_tokens) AS total_prompt_tokens",
      "SUM(cached_tokens) AS total_cached_tokens",
      "SUM(completion_tokens) AS total_completion_tokens",
      "SUM(total_tokens) AS total_tokens",
      "SUM(total_cost) AS total_costs"
    )
  end
end
