# To automate setup of Active Record Encryption keys, first we need to make sure there is a master key and credentials file.
namespace :credentials do
  desc "Initialize Rails credentials. Ensures master key and credentials file exist."
  # As we can't load the production Rails environment in production without the secret_key_base,
  # use a minimal Rails loading approach for this task.
  # The generated credentials will then include a secret_key_base.
  task :setup do
    puts "Running credentials:setup task, for environment #{ENV["RAILS_ENV"]}..."

    require "rails"

    # Since this app is Dockerized for production, RAILS_MASTER_KEY should be set in production.
    if ENV["RAILS_ENV"] == "production"
      unless ENV["RAILS_MASTER_KEY"]
        puts "WARNING: RAILS_MASTER_KEY missing. The production master key is going to be added to the container's ephemeral file system, and will be lost when the container is stopped."
        puts "The generated key is also going to be leaked to the log."
      end
    end

    # For development, this task will generate a master key if it doesn't exist.
    # Rails supports separate master keys and credentials files for different environments.
    # We'll use the environment-specific credentials file.
    prod_credentials_path = File.expand_path("../../config/credentials/production.yml.enc", __dir__)
    dev_credentials_path = File.expand_path("../../config/credentials/development.yml.enc", __dir__)
    test_credentials_path = File.expand_path("../../config/credentials/test.yml.enc", __dir__)

    # Determine which credentials file to use based on environment
    credentials_path = case ENV["RAILS_ENV"]
    when "production"
      prod_credentials_path
    when "test"
      test_credentials_path
    when "development"
      dev_credentials_path
    else
      raise "Unknown environment: #{ENV["RAILS_ENV"]}"
    end

    if !File.exist?(credentials_path)
      puts "Credentials file missing. Attempting to initialize..."
      # The EDITOR=true trick makes `credentials:edit` create the files non-interactively if they don't exist.
      # This will also create the master key if it doesn't exist.
      # We check the success of this system call.
      success = system({ "EDITOR" => "true" }, "bin/rails credentials:edit --environment=#{ENV["RAILS_ENV"]}")

      unless success
        STDERR.puts "ERROR: Failed to initialize credentials. Cannot proceed."
        exit 1 # Critical failure
      end
      # Verify that the file was indeed created.
      unless File.exist?(credentials_path)
        STDERR.puts "ERROR: Failed to create credentials file"
        exit 1 # Critical failure
      end
      puts "INFO: Credentials file initialized."
    else
      puts "#{credentials_path} already exists."
    end
  end
end
