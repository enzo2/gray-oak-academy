
# We use to_prepare to ensure that this patch is applied correctly in development
# mode (where classes are reloaded) and in production (where they are eager-loaded).
Rails.application.config.to_prepare do
  Turbo::Streams::ActionBroadcastJob.class_eval do
    limits_concurrency to: 1, key: ->(streamable, options) do
      # --- START DEBUG LOGGING ---
      key_from_locals = options.dig(:locals, :message)
      target = options[:target]

      # Log what we're seeing to the console/log file
      Rails.logger.info <<~LOG
        -----> [SolidQueue Turbo Patch]
               Streamable: #{streamable}
               Target:     #{target.inspect}
               Key Source: #{key_from_locals.try(:to_global_id) || 'NIL from locals'}
               Options:    #{options.keys}
      LOG
      # --- END DEBUG LOGGING ---

      # Return the original key logic
      key_from_locals
    end
  end
end
