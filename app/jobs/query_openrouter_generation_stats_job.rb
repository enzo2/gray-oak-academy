# No longer needed because OpenRouter supports returning the stats with the response.
class QueryOpenrouterGenerationStatsJob < ApplicationJob
  queue_as :default

  # Job should be called after a little delay, or 404 may be returned.
  # eg. QueryOpenrouterGenerationStatsJob.set(wait: 10.seconds).perform_later(id, user)
  def perform(id:, user:, conversation: nil)
    begin
      stats = OpenRouterService.new(user: user).query_generation_stats(id)
      # looks like: Generation stats: {"id"=>"gen-1729460228-8UG48Afj6vSSmQm81FEb", "upstream_id"=>"msg_012x1buMaUWbN5d6jhv2Qd7U", "total_cost"=>0.004902, "cache_discount"=>0, "created_at"=>"2024-10-20T21:37:12.820903+00:00", "model"=>"anthropic/claude-3.5-sonnet:beta", "app_id"=>179379, "streamed"=>true, "cancelled"=>false, "provider_name"=>"Anthropic", "latency"=>1166, "moderation_latency"=>nil, "generation_time"=>2789, "finish_reason"=>"end_turn", "tokens_prompt"=>1048, "tokens_completion"=>91, "native_tokens_prompt"=>1144, "native_tokens_completion"=>98, "native_tokens_reasoning"=>nil, "num_media_prompt"=>nil, "num_media_completion"=>nil, "origin"=>"https://github.com/OlympiaAI/open_router", "usage"=>0.004902}
      total_native_tokens = stats["native_tokens_prompt"].to_i +  stats["native_tokens_completion"].to_i
      total_tokens = stats["tokens_prompt"].to_i + stats["tokens_completion"].to_i

      generation_stats = Completion.create(
        conversation: conversation,
        model: stats["model"],
        api_provider: user.settings.llm_api_base_uri.presence || ENV.fetch("OPENAI_API_BASE_URI"),
        model_provider: stats["provider_name"],
        total_cost: stats["total_cost"].to_f,
        cache_discount: stats["cache_discount"].to_f,
        prompt_tokens: stats["native_tokens_prompt"].to_i || stats["tokens_prompt"].to_i,
        reasoning_tokens: stats["native_tokens_reasoning"].to_i,
        completion_tokens:  stats["native_tokens_completion"].to_i || stats["tokens_completion"].to_i,
        total_tokens: total_native_tokens || total_tokens,
        latency: stats["latency"].to_i,
        generation_time: stats["generation_time"].to_i
      )
      Rails.logger.info("Generation stats saved successfully: #{generation_stats.inspect}")
    rescue StandardError => e
      Rails.logger.error("Error querying generation stats: #{e.message}")
    end
  end
end
