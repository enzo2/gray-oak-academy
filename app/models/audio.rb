class Audio < ApplicationRecord
  belongs_to :message
  has_one_attached :file

  # Gemini supports more audio formats types than OpenAI.
  # OpenAI only wav and mp3.


  def to_base64_wav
    return nil unless file.attached?

    # Download the original file to a temporary location
    temp_webm = Tempfile.new([ "input", ".webm" ])
    temp_wav = Tempfile.new([ "output", ".wav" ])
    begin
      temp_webm.binmode
      file.download { |chunk| temp_webm.write(chunk) }
      temp_webm.rewind

      # Use ffmpeg to convert webm (opus) to wav
      # Specify sample rate for output WAV
      # `-ac 1` forces mono channel
      # `-ar 24000` sets the sample rate
      # `-y` overwrites output file without asking
      command = "ffmpeg -i #{temp_webm.path} -ar 24000 -ac 1 -y #{temp_wav.path}"
      Rails.logger.debug "Running ffmpeg command: #{command}"
      system(command)

      unless File.exist?(temp_wav.path) && File.size(temp_wav.path) > 0
         Rails.logger.error "FFmpeg conversion failed or produced an empty file."
         return nil
      end

      # Read the converted WAV file and encode to base64
      wav_data = File.read(temp_wav.path)
      Base64.strict_encode64(wav_data)
    rescue StandardError => e
      Rails.logger.error "Error during audio conversion or encoding: #{e.message}"
      nil
    ensure
      temp_webm.close
      temp_webm.unlink # deletes the temp file
      temp_wav.close
      temp_wav.unlink # deletes the temp file
    end
  end

  # For future use
  def to_base64_mp3
    return nil unless file.attached?

    # Download the original file to a temporary location
    temp_webm = Tempfile.new([ "input", ".webm" ])
    temp_mp3 = Tempfile.new([ "output", ".mp3" ])
    begin
      temp_webm.binmode
      file.download { |chunk| temp_webm.write(chunk) }
      temp_webm.rewind

      # Use ffmpeg to convert webm (opus) to mp3
      # `-ac 1` forces mono channel
      # `-ar 24000` sets the sample rate
      # `-b:a 32k` sets the bitrate to 32kbps which is good for speech
      # `-y` overwrites output file without asking
      command = "ffmpeg -i #{temp_webm.path} -ar 24000 -ac 1 -b:a 64k -y #{temp_mp3.path}"
      Rails.logger.debug "Running ffmpeg command: #{command}"
      system(command)

      unless File.exist?(temp_mp3.path) && File.size(temp_mp3.path) > 0
        Rails.logger.error "FFmpeg conversion failed or produced an empty file."
        return nil
      end

      # Read the converted MP3 file and encode to base64
      mp3_data = File.read(temp_mp3.path)
      Base64.strict_encode64(mp3_data)
    rescue StandardError => e
      Rails.logger.error "Error during audio conversion or encoding: #{e.message}"
      nil
    ensure
      temp_webm.close
      temp_webm.unlink # deletes the temp file
      temp_mp3.close
      temp_mp3.unlink # deletes the temp file
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
