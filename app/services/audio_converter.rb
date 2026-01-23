# Utility to convert audio files to 24kHz mono WAV and return Base64-encoded content.
class AudioConverter
  require "tempfile"
  require "base64"

  def self.convert_to_base64_wav(input_path)
    return nil unless input_path && File.exist?(input_path)

    temp_wav = Tempfile.new([ "stt_input", ".wav" ])
    begin
      # ffmpeg: convert to 24kHz mono wav
      # -y to overwrite, -ar 24000 sample rate, -ac 1 forces mono
      ffmpeg_args = [ "ffmpeg", "-i", input_path, "-ar", "24000", "-ac", "1", "-y" ]
      ffmpeg_args += [ "-loglevel", "error" ] if Rails.env.test?
      ffmpeg_args << temp_wav.path

      system(*ffmpeg_args)

      unless File.exist?(temp_wav.path) && File.size(temp_wav.path) > 0
        Rails.logger.error "FFmpeg conversion failed or produced an empty file for input: #{input_path}"
        return nil
      end

      Base64.strict_encode64(File.read(temp_wav.path))
    rescue StandardError => e
      Rails.logger.error "Error during audio conversion or encoding: #{e.message}"
      nil
    ensure
      temp_wav.close
      temp_wav.unlink
    end
  end
end
