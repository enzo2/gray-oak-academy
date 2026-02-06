class OpenAiError < StandardError; end

# Optional clearer alias while preserving backwards compatibility.
OpenAiWrapperError = OpenAiError unless defined?(OpenAiWrapperError)
