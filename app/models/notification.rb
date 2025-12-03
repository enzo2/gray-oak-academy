class Notification < ApplicationRecord
  belongs_to :recipient, class_name: "User"

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current)
  end

  def message
    definition.message % (params || {}).symbolize_keys
  rescue StandardError => e
    Rails.logger.error "Failed to generate notification message: #{e.message}"
    "New notification: #{event_type}"
  end

  def definition
    Type.find(event_type)
  rescue ArgumentError
    Type.missing(event_type)
  end

  # Notification::Type is the canonical source of truth for notification event definitions.
  # It loads from config/notifications.yml and is referenced by Events::Base subclasses.
  class Type
    attr_reader :name, :category, :subject, :message, :required_params

    def self.find(name)
      all[name.to_s] || raise(ArgumentError, "Unknown notification type: #{name}")
    end

    def self.missing(name)
      # Return a default "missing" notification type
      new(
        name: name,
        category: "system",
        subject: "Notification",
        message: "Notification: #{name}",
        required_params: []
      )
    end

    def self.all
      @all ||= load_config
    end

    # Clear cached config (useful for testing or config reload)
    def self.reset!
      @all = nil
    end

    def initialize(name:, category:, subject:, message:, required_params:)
      @name = name
      @category = category
      @subject = subject
      @message = message
      @required_params = (required_params || []).map(&:to_s)
    end

    # Validate that all required params are present in the given hash
    def validate_params!(params)
      param_keys = params.keys.map(&:to_s)
      missing = required_params - param_keys
      if missing.any?
        raise ArgumentError, "Missing required params for #{name}: #{missing.join(', ')}"
      end
    end

    private_class_method def self.load_config
      config_path = Rails.root.join("config", "notifications.yml")
      config = YAML.safe_load(File.read(config_path), aliases: true)
      config["events"].each_with_object({}) do |(name, data), hash|
        hash[name] = new(
          name: name,
          category: data["category"],
          subject: data["subject"],
          message: data["message"],
          required_params: data["required_params"]
        )
      end
    end
  end
end
