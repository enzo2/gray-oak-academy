class LlmUsageAccountingService
  COST_TICK_DIVISOR = 10_000_000_000

  def self.enforce_cost_limits!(user:, conversation:)
    daily_budget = user.daily_budget
    max_chat_cost = AppSetting.settings&.max_chat_cost

    return unless daily_budget.present? || max_chat_cost.present?

    enforce_daily_budget!(user: user, conversation: conversation, daily_budget: daily_budget) if daily_budget.present?
    enforce_chat_budget!(user: user, conversation: conversation, max_chat_cost: max_chat_cost) if conversation && max_chat_cost.present?
  end

  def self.usage_total_cost(usage)
    cost = usage&.dig("cost")
    return cost.to_f if cost.present?

    ticks = usage&.dig("cost_in_usd_ticks")
    return nil if ticks.blank?

    BigDecimal(ticks.to_s) / COST_TICK_DIVISOR
  end

  def self.notify_admins_of_limit(user:, reason:)
    superuser_ids = User.role_superuser.pluck(:id)
    return if superuser_ids.empty?

    Rails.event.notify(Events::UserLimitExceeded.new(
      recipient_ids: superuser_ids,
      link: Rails.application.routes.url_helpers.admin_student_path(user),
      user_name: user.name,
      user_id: user.id,
      reason: reason
    ))
  rescue StandardError => e
    Rails.logger.error "Failed to notify admins of limit: #{e.message}"
  end

  def self.enforce_daily_budget!(user:, conversation:, daily_budget:)
    daily_spend = Completion.where(user: user).in_date_range(Date.current, Date.current).sum(:total_cost)
    return unless daily_spend >= daily_budget

    in_active_lesson = conversation&.lesson_progress.present? && !conversation.lesson_progress.completed?
    lesson_overage_limit = daily_budget * 1.25
    over_lesson_allowance = daily_spend >= lesson_overage_limit

    return if in_active_lesson && !over_lesson_allowance

    message = if in_active_lesson && over_lesson_allowance
      "Daily API usage budget exceeded even after lesson allowance."
    else
      "Daily API usage budget has been exceeded. Please try again tomorrow."
    end
    notify_admins_of_limit(user: user, reason: message)
    raise OpenAiError, message
  end
  private_class_method :enforce_daily_budget!

  def self.enforce_chat_budget!(user:, conversation:, max_chat_cost:)
    chat_spend = Completion.where(conversation: conversation).sum(:total_cost)
    return unless chat_spend >= max_chat_cost

    message = "This chat has exceeded the maximum cost limit. Please start a new one."
    notify_admins_of_limit(user: user, reason: message)
    raise OpenAiError, message
  end
  private_class_method :enforce_chat_budget!
end
