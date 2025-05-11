namespace :encryption do
  desc "Initialize Rails credentials and ActiveRecord encryption keys if not present. Ensures master key and credentials file exist."
  task setup: :environment do
    puts "Running encryption:setup task..."

    # --- 1. Ensure master key and credentials file exist ---
    # prod_credentials_path = Rails.root.join("config/credentials/production.yml.enc")
    # dev_credentials_path = Rails.root.join("config/credentials/development.yml.enc")
    # credentials_path = Rails.env.production? ? prod_credentials_path : dev_credentials_path
    credentials_path = Rails.root.join("config/credentials.yml.enc")

    if !credentials_path.exist?
      puts "Credentials file missing. Attempting to initialize..."
      # The EDITOR=true trick makes `credentials:edit` create the files non-interactively if they don't exist.
      # We check the success of this system call.
      # success = system({ "EDITOR" => "true" }, "bin/rails credentials:edit --environment=#{Rails.env}")
      success = system({ "EDITOR" => "true" }, "bin/rails credentials:edit")
      unless success
        STDERR.puts "ERROR: 'bin/rails credentials:edit' failed during initialization. Cannot proceed."
        exit 1 # Critical failure
      end
      # Verify that the file was indeed created.
      unless credentials_path.exist?
        STDERR.puts "ERROR: Failed to create credentials file"
        exit 1 # Critical failure
      end
      puts "INFO: Master key and credentials file initialized."
    else
      puts "#{credentials_path} already exists."
    end

    # --- 2. Check if keys already exist (Idempotency) ---
    begin
      current_credentials_config = Rails.application.credentials.config
      if current_credentials_config.dig(:active_record_encryption, :primary_key).present?
        puts "ActiveRecord encryption keys already exist in credentials. No changes needed."
        exit 0 # Successful, no action taken
      end
    rescue ActiveSupport::EncryptedFile::MissingKeyError
      # Handle the case where the master key is missing.
      STDERR.puts "ERROR: Rails master key is missing. Add a key, such as config/credentials/production.key."
      STDERR.puts "Cannot read credentials. Please ensure the master key is available."
      exit 1
    rescue StandardError => e
      # Catch other errors during the read operation (e.g., malformed credentials file).
      STDERR.puts "ERROR: Could not access or parse Rails credentials for checking: #{e.class} - #{e.message}"
      exit 1
    end

    # --- 3. Add keys if they don't exist ---
    puts "INFO: Adding ActiveRecord encryption keys to credentials..."
    begin
      # Rails.application.credentials.change handles decryption to a temp file,
      # allows modification, and then handles re-encryption and saving.
      Rails.application.credentials.change do |tmp_credentials_path|
        # tmp_credentials_path points to a temporary file with the decrypted YAML content.
        current_yaml_content = File.read(tmp_credentials_path)

        # Load YAML. `safe_load` is preferred. `aliases: true` is good for Rails YAML.
        # This will produce a hash with string keys, matching typical YAML structure.
        editable_yaml_hash = YAML.safe_load(current_yaml_content, aliases: true) || {}

        # Ensure the nested hash structure exists, using string keys for YAML.
        editable_yaml_hash["active_record_encryption"] ||= {}
        editable_yaml_hash["active_record_encryption"]["primary_key"] = SecureRandom.alphanumeric(32)
        editable_yaml_hash["active_record_encryption"]["deterministic_key"] = SecureRandom.alphanumeric(32)
        editable_yaml_hash["active_record_encryption"]["key_derivation_salt"] = SecureRandom.alphanumeric(32)

        # Convert the modified hash back to YAML.
        new_yaml_content = YAML.dump(editable_yaml_hash)

        # Write the new YAML content back to the temporary file.
        File.write(tmp_credentials_path, new_yaml_content)
      end
      puts "SUCCESS: ActiveRecord encryption keys have been added to credentials."
    rescue ActiveSupport::EncryptedFile::MissingKeyError
      # This could happen if the master key disappears between the initial check and this `change` block.
      STDERR.puts "ERROR: Rails master key went missing before credentials could be changed."
      exit 1
    rescue StandardError => e
      # Catch any other errors during the modification process.
      STDERR.puts "ERROR: Failed to change credentials: #{e.class} - #{e.message}"
      e.backtrace.first(5).each { |line| STDERR.puts "  #{line}" } # Print a short trace
      exit 1
    end
  end
end
