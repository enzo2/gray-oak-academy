class NotificationsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_notification, only: [ :update, :destroy ]

  def index
    @notifications = current_user.notifications.recent.limit(50)
  end

  # Only update is to mark as read
  def update
    @notification.mark_as_read!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: notifications_path }
    end
  end

  def destroy
    @notification.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: notifications_path }
    end
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read_at: Time.current)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: notifications_path }
    end
  end

  private

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  end
end
