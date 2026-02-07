class SupportedApi < ApplicationRecord
  # Shared/supported OpenAI-compatible API configuration managed by superusers.

  # Encrypt the shared token in the DB
  encrypts :api_access_token

  before_validation :ensure_trailing_slash
  before_validation :nilify_blank_access_token

  validates :api_base_uri, presence: true, uniqueness: true

  # Only selectable for teachers if enabled and has a token
  scope :enabled, -> { where(enabled: true) }
  scope :with_token, -> { where.not(api_access_token: nil) }
  scope :selectable_for_teachers, -> { enabled.with_token }
  scope :openai_platform, -> { where("api_base_uri LIKE ?", "https://api.openai.com/%") }

  def self.selectable_uris
    selectable_for_teachers.pluck(:api_base_uri)
  end

  def self.openai_supported
    # Assumes one OpenAI Platform base URI entry for now; if multiple are added,
    # AppSetting should explicitly store which SupportedApi record to use.
    openai_platform.first
  end

  def self.openai_selectable
    # Assumes one OpenAI Platform base URI entry for now; if multiple are added,
    # AppSetting should explicitly store which SupportedApi record to use.
    selectable_for_teachers.openai_platform.first
  end

  private

  def ensure_trailing_slash
    return if api_base_uri.blank?
    self.api_base_uri = api_base_uri.end_with?("/") ? api_base_uri : "#{api_base_uri}/"
  end

  def nilify_blank_access_token
    self.api_access_token = nil if api_access_token.blank?
  end
end
