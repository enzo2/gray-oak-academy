class QueryOpenrouterGenerationStatsJob < ApplicationJob
  queue_as :default

  # Job should be called after a little delay, or 404 may be returned.
  # eg. QueryOpenrouterGenerationStatsJob.set(wait: 5.seconds).perform_later(id)
  def perform(id)
    begin
      stats = OpenRouterService.new.query_generation_stats(id)
      # looks like: Generation stats: {"id"=>"gen-1729460228-8UG48Afj6vSSmQm81FEb", "upstream_id"=>"msg_012x1buMaUWbN5d6jhv2Qd7U", "total_cost"=>0.004902, "cache_discount"=>0, "created_at"=>"2024-10-20T21:37:12.820903+00:00", "model"=>"anthropic/claude-3.5-sonnet:beta", "app_id"=>179379, "streamed"=>true, "cancelled"=>false, "provider_name"=>"Anthropic", "latency"=>1166, "moderation_latency"=>nil, "generation_time"=>2789, "finish_reason"=>"end_turn", "tokens_prompt"=>1048, "tokens_completion"=>91, "native_tokens_prompt"=>1144, "native_tokens_completion"=>98, "native_tokens_reasoning"=>nil, "num_media_prompt"=>nil, "num_media_completion"=>nil, "origin"=>"https://github.com/OlympiaAI/open_router", "usage"=>0.004902}
      total_cost = stats["total_cost"]
      prompt_tokens = stats["native_tokens_prompt"]
      completion_tokens = stats["native_tokens_completion"]
      latency = stats["latency"]

      # Placeholder for saving usage info to the DB
      Rails.logger.debug("Generation stats - Prompt tokens: #{prompt_tokens}, Completion tokens: #{completion_tokens}")
      Rails.logger.debug("Cost: #{total_cost}")
      Rails.logger.debug("Latency: #{latency} ms")
    rescue StandardError => e
      Rails.logger.error("Error querying generation stats: #{e.message}")
    end
  end
end
