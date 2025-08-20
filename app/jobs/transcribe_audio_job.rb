class TranscribeAudioJob < ApplicationJob
  queue_as :default

  # Set ActiveJob uniqueness strategy if available (e.g., with SolidQueue)
  # unique_until: :success, lock_ttl: 1.hour # Example, adjust as needed

  discard_on ActiveJob::DeserializationError # Ignore if the record is deleted before job runs
  retry_on SpeechService::SpeechServiceError, wait: :exponentially_longer, attempts: 2 # Retry on STT API errors

  def perform(audio:)
    unless audio && audio.file.attached?
      Rails.logger.warn "TranscribeAudioJob: Audio record with ID #{audio.id} not found. Skipping."
      return
    end

    message = audio.message
    user = message.conversation.user

    Rails.logger.info "TranscribeAudioJob: Starting transcription for Audio ID #{audio.id} (Message ID: #{message.id})"
    begin
      speech_service = SpeechService.new(current_user: user, conversation: message.conversation)
      # Create a temporary file to pass to the service
      audio.file.open do |tempfile|
        transcription_text = speech_service.transcribe(tempfile)

        # Check if the transcription was successful
        raise SpeechService::SpeechServiceError, "Transcription failed: No text returned" if transcription_text.blank?
        Rails.logger.info "TranscribeAudioJob: Successfully transcribed Audio ID #{audio.id}"
        Rails.logger.debug "TranscribeAudioJob: Transcription text: #{transcription_text}"

        message.update!(content: transcription_text)
        Rails.logger.info "TranscribeAudioJob: Successfully updated Message ID #{message.id}"

        audio.destroy # this will also purge_later the file
        Rails.logger.info "TranscribeAudioJob: Purged Audio ID #{audio.id}"

        # No need to broadcast here; the message update will trigger the callback to broadcast
      end

    rescue SpeechService::SpeechServiceError => e
      Rails.logger.error "TranscribeAudioJob: STT failed for Audio ID #{audio.id}. Error: #{e.message}"
      # Let ActiveJob handle retries based on retry_on configuration
      raise e # Re-raise to trigger retry
    rescue StandardError => e
      Rails.logger.error "TranscribeAudioJob: Unexpected error for Audio ID #{audio.id}. Error: #{e.class.name} - #{e.message}\n#{e.backtrace.join("\n")}"
      raise e # Re-raise to potentially trigger retry depending on global config
    end
  end
end
