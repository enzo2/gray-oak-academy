class Audio < ApplicationRecord
  belongs_to :message
  has_one_attached :file# , dependent: :purge_later   default is purge_later

  # Gemini supports more audio formats types than OpenAI. OpenAI only wav and mp3.
  # Therefore, we will convert to wav for now. Ideally all providers should support webm with opus.

  def to_base64_wav
    return nil unless file.attached?

    temp_wav = Tempfile.new([ "output", ".wav" ])
    begin
      file.open do |temp_webm|
        # Use ffmpeg to convert webm (opus) to wav
        # `-ac 1` forces mono channel
        # `-ar 24000` sets the sample rate
        system("ffmpeg", "-i", temp_webm.path, "-ar", "24000", "-ac", "1", "-y", temp_wav.path)

        unless File.exist?(temp_wav.path) && File.size(temp_wav.path) > 0
           Rails.logger.error "FFmpeg conversion failed or produced an empty file."
           return nil # Return nil from the block, which file.open will return
        end

        Base64.strict_encode64(File.read(temp_wav.path))
      end # temp_webm is automatically closed and unlinked here
    rescue StandardError => e
      Rails.logger.error "Error during audio conversion or encoding: #{e.message}"
      nil
    ensure
      temp_wav.close
      temp_wav.unlink # deletes the temp file
    end
  end

  def base64_for_LLM
    return nil unless file.attached?
    {
      data: to_base64_wav,
      format: "wav"
    }
  end
end
