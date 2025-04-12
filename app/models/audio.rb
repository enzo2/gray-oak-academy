class Audio < ApplicationRecord
  belongs_to :message
  has_one_attached :file

  # Gemini supports more audio formats types than OpenAI.
  # OpenAI only wav and mp3.
  # We'll send the wav, but convert to a lossy format for storage.

  def to_base64
    return nil unless file.attached?
    Base64.strict_encode64(file.download)
  end

  def base64_for_LLM
    return nil unless file.attached?
    {
      data: to_base64,
      format: "wav"
    }
  end
end
