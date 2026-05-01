require "digest"
require "securerandom"

class AgentApiKey < ApplicationRecord
  TOKEN_PREFIX = "goa_live_".freeze
  VISIBLE_PREFIX_LENGTH = 18

  belongs_to :user
  has_many :agent_api_events, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :token_digest, presence: true, uniqueness: true
  validates :visible_prefix, presence: true
  validate :user_must_be_teacher

  scope :active, -> { where(revoked_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  def self.create_with_token!(user:, name:)
    token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    key = create!(
      user: user,
      name: name.to_s.strip.presence || "Agent key",
      token_digest: digest_token(token),
      visible_prefix: token.first(VISIBLE_PREFIX_LENGTH)
    )
    [ key, token ]
  end

  def self.authenticate(raw_token)
    token = raw_token.to_s.strip
    return nil unless token.start_with?(TOKEN_PREFIX)

    key = active.includes(:user).find_by(token_digest: digest_token(token))
    return nil unless key

    expected = key.token_digest.to_s
    actual = digest_token(token)
    return nil unless ActiveSupport::SecurityUtils.secure_compare(expected, actual)

    key.touch(:last_used_at)
    key
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  private

  def user_must_be_teacher
    return if user&.role_teacher?

    errors.add(:user, "must be a teacher")
  end
end
