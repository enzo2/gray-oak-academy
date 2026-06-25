# Converts a raised background-generation error into teacher-facing text.
# Provider errors embed HTTP status codes and raw JSON bodies that are noise for
# teachers, so known error types are rewritten into a plain explanation. Unknown
# errors fall back to their own message unchanged.
#
# `scope` tailors the recovery advice for a Codex usage-limit error, because the
# same error surfaces from two different routes:
#   :personal         -> the teacher's own configured model (e.g. lesson plan
#                        content generation). Recovery is to switch their model.
#   :background_agent  -> a background agent run, which can be backed by a shared
#                        provider. Recovery is to configure that shared provider.
module GenerationErrorPresenter
  module_function

  def friendly(error, scope: :background_agent)
    case error
    when BackgroundAgentConfigResolver::CodexUsageLimitError
      usage_limit_message(error, scope: scope)
    else
      error.message
    end
  end

  def usage_limit_message(error, scope: :background_agent)
    plan = error.plan_type.present? ? " #{error.plan_type.to_s.titleize}" : ""
    reset = reset_clause(error.resets_at)

    if scope == :personal
      "Your ChatGPT#{plan} usage limit has been reached, so this run could not complete.#{reset} " \
        "Try again after it resets, or switch to another model under Settings > LLMs."
    else
      "Your ChatGPT#{plan} usage limit for background runs has been reached.#{reset} " \
        "You can retry later, or have a superuser configure a shared background-agent provider in App Settings."
    end
  end

  def reset_clause(resets_at)
    return "" if resets_at.blank? || resets_at <= Time.current

    " Access resets in about #{ActionController::Base.helpers.distance_of_time_in_words(Time.current, resets_at)}."
  end
end
