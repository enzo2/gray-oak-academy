module Admin
  class AnalyticsEventsController < Admin::BaseController
    before_action :require_superuser

    def index
      @events = analytics_events.first(500)
    end

    def clear
      app_setting = AppSetting.settings

      if app_setting
        app_setting.with_lock do
          log = (app_setting.log || {}).deep_dup
          log["analytics_events"] = []
          settings = app_setting.settings.deep_dup
          settings.delete("analytics_events")
          app_setting.update!(log: log, settings: settings)
        end
      end

      redirect_to admin_analytics_events_path, notice: "Analytics logs cleared."
    end

    private

    def analytics_events
      app_setting = AppSetting.settings
      return [] unless app_setting

      Array((app_setting.log || {})["analytics_events"]).filter_map do |event|
        normalize_event(event)
      end
    end

    def normalize_event(event)
      entry = event.is_a?(Hash) ? event.deep_symbolize_keys : {}
      return nil if entry.blank?

      {
        event_type: entry[:event_type].to_s,
        category: entry[:category].to_s,
        subject: entry[:subject].to_s,
        message: entry[:message].to_s,
        link: entry[:link].to_s.presence,
        recipient_ids: Array(entry[:recipient_ids]),
        params: entry[:params].is_a?(Hash) ? entry[:params] : {},
        emitted_at: entry[:emitted_at].to_s
      }
    end
  end
end
