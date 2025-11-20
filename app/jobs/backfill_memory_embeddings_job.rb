class BackfillMemoryEmbeddingsJob < ApplicationJob
  queue_as :default

  def perform
    return unless AppSetting.embeddings_configured?

    memories = Memory.where(embedding: nil)
    total = memories.count
    Rails.logger.info "Starting backfill of #{total} memory embeddings..."

    memories.find_each(batch_size: 100) do |memory|
      begin
        memory.update_embedding
      rescue StandardError => e
        Rails.logger.error "Failed to backfill embedding for Memory #{memory.id}: #{e.message}"
      end
    end

    Rails.logger.info "Completed backfill of memory embeddings."
  end
end
