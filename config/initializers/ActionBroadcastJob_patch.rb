
# We use to_prepare to ensure that this patch is applied correctly in development
# mode (where classes are reloaded) and in production (where they are eager-loaded).
Rails.application.config.to_prepare do
  # Re-open the Turbo::Streams::ActionBroadcastJob to add SolidQueue-specific features.
  Turbo::Streams::ActionBroadcastJob.class_eval do
    # This is the SolidQueue feature for controlling concurrency.
    # It ensures that jobs with the same key are processed sequentially.
    limits_concurrency to: 1, key: ->(streamable, options) do
      # The options hash contains the locals passed to the broadcast.
      # For a message stream, this will be { message: <GlobalID of the Message> }.
      # We dig into the options to find the message object.
      # SolidQueue automatically converts the Active Record object (via its GlobalID)
      # into a stable string key like "gid://my-app/Message/19".
      # This means all jobs for Message/19 will be serialized, but jobs
      # for Message/20 can run at the same time.
      options.dig(:locals, :message)
    end
  end
end
