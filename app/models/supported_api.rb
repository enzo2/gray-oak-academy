class SupportedApi < ApplicationRecord
  OPENAI_BASE_URI = "https://api.openai.com/v1/".freeze
  OPENROUTER_BASE_URI = "https://openrouter.ai/api/v1/".freeze
  OPENAI_CODEX_BASE_URI = "https://chatgpt.com/backend-api/codex/".freeze
  XAI_BASE_URI = "https://api.x.ai/v1/".freeze
  RESPONSES_AGENT_BASE_URIS = [ OPENAI_BASE_URI, OPENROUTER_BASE_URI, XAI_BASE_URI ].freeze
  SPEECH_PROVIDER_BASE_URIS = [ OPENAI_BASE_URI, OPENROUTER_BASE_URI ].freeze

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
  scope :responses_agent_compatible, -> { where(api_base_uri: RESPONSES_AGENT_BASE_URIS) }
  scope :speech_compatible, -> { where(api_base_uri: SPEECH_PROVIDER_BASE_URIS) }

  def self.selectable_uris
    selectable_for_teachers.pluck(:api_base_uri)
  end

  def self.openai_supported
    find_by(api_base_uri: OPENAI_BASE_URI)
  end

  def self.xai_supported
    find_by(api_base_uri: XAI_BASE_URI)
  end

  def self.openrouter_supported
    find_by(api_base_uri: OPENROUTER_BASE_URI)
  end

  def self.speech_providers
    speech_compatible.order(:api_base_uri)
  end

  def self.openai_selectable
    selectable_for_teachers.find_by(api_base_uri: OPENAI_BASE_URI)
  end

  def self.xai_selectable
    selectable_for_teachers.find_by(api_base_uri: XAI_BASE_URI)
  end

  def self.responses_agent_selectable
    selectable_for_teachers.responses_agent_compatible
  end

  def self.find_responses_agent_selectable_by_id(id)
    return nil unless id.present?

    responses_agent_selectable.find_by(id: id.to_i)
  end

  def self.find_responses_agent_selectable_by_base_uri(base_uri)
    normalized_uri = normalize_base_uri(base_uri)
    return nil if normalized_uri.blank?

    responses_agent_selectable.find_by(api_base_uri: normalized_uri)
  end

  def self.normalize_base_uri(base_uri)
    value = base_uri.to_s.strip
    return "" if value.blank?

    value.end_with?("/") ? value : "#{value}/"
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
