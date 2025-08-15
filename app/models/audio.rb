class Audio < ApplicationRecord
  belongs_to :message
  has_one_attached :file# , dependent: :purge_later   default is purge_later

  # Gemini supports more audio formats types than OpenAI. OpenAI and OpenRouter, only wav and mp3.
  # Therefore, we will convert to wav for now. Ideally all providers should support webm with opus.
  #
  # Could experiment with the wav vs. mp3 conversion time, since smaller uploads preferable.

  def to_base64_wav
    return nil unless file.attached?

    # Use the shared AudioConverter to handle ffmpeg conversion and base64 encoding.
    file.open do |tempfile|
      AudioConverter.convert_to_base64_wav(tempfile.path)
    end
  rescue StandardError => e
    Rails.logger.error "Error during audio conversion or encoding: #{e.message}"
    nil
  end

  def base64_for_LLM
    return nil unless file.attached?
    {
      data: to_base64_wav,
      format: "wav"
    }
  end
end
