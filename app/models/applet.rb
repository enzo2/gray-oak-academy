class Applet < ApplicationRecord
  SANDBOX_PERMISSIONS = %w[
    allow-scripts
    allow-modals
    allow-pointer-lock
    allow-popups
    allow-presentation
    allow-forms
    allow-downloads
  ].freeze
  SANDBOX_ATTRIBUTE = SANDBOX_PERMISSIONS.join(" ").freeze

  belongs_to :user
  belongs_to :resource, optional: true

  validates :title, presence: true
  validates :code, presence: true

  validate :validate_js_syntax, if: :code_changed?

  private

  def validate_js_syntax
    return if code.blank?
    syntax_check = NodeJsSyntaxChecker.check(code)
    unless syntax_check[:valid]
      errors.add(:code, "JavaScript syntax errors: #{syntax_check[:errors].join('; ')}")
    end
  end
end
