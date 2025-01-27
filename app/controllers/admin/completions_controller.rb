module Admin
  class CompletionsController < ApplicationController
  before_action :require_admin

    def index
      @usage_data = Completion.group(:model, :api_provider)
      .select(
        :model,
        :api_provider,
        "SUM(prompt_tokens) AS total_prompt_tokens",
        "SUM(completion_tokens) AS total_completion_tokens",
        "SUM(total_tokens) AS total_tokens",
        "SUM(total_cost) AS total_costs"
      )
    end
  end
end
