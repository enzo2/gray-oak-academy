require "test_helper"
require "selenium-webdriver"

# Register custom Chrome drivers with media/testing flags
Capybara.register_driver :headless_chrome_with_media do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  %w[
    --headless=new
    --use-fake-ui-for-media-stream
    --use-fake-device-for-media-stream
    --autoplay-policy=no-user-gesture-required
    --no-sandbox
    --allow-insecure-localhost
    --mute-audio
    --disable-dev-shm-usage
    --window-size=1400,1400
  ].each { |arg| options.add_argument(arg) }

  fake_audio = Rails.root.join("test/fixtures/files/sample.wav")
  options.add_argument("--use-file-for-fake-audio=#{fake_audio}") if File.exist?(fake_audio)

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.register_driver :remote_headless_chrome_with_media do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  %w[
    --headless=new
    --use-fake-ui-for-media-stream
    --use-fake-device-for-media-stream
    --autoplay-policy=no-user-gesture-required
    --no-sandbox
    --allow-insecure-localhost
    --mute-audio
    --disable-dev-shm-usage
    --window-size=1400,1400
  ].each { |arg| options.add_argument(arg) }

  fake_audio = Rails.root.join("test/fixtures/files/sample.wav")
  options.add_argument("--use-file-for-fake-audio=#{fake_audio}") if File.exist?(fake_audio)

  # Allow getUserMedia on non-secure host used by remote server (rails-app)
  if ENV["CAPYBARA_SERVER_PORT"]
    insecure_origin = "http://rails-app:#{ENV["CAPYBARA_SERVER_PORT"]}"
    options.add_argument("--unsafely-treat-insecure-origin-as-secure=#{insecure_origin}")
  end

  Capybara::Selenium::Driver.new(
    app,
    browser: :remote,
    url: "http://#{ENV.fetch("SELENIUM_HOST")}:4444",
    options: options
  )
end

module SystemTestAuthenticationHelpers
  def sign_in(user, password: "password")
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_on "Log in"
    unless page.has_text?("Dashboard", wait: 5)
      raise "Login did not complete as expected for user: #{user.email}"
    end
  end
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include SystemTestAuthenticationHelpers
  include ActiveJob::TestHelper
  include TestSupport::SpeechStubs if defined?(TestSupport::SpeechStubs)

  if ENV["CAPYBARA_SERVER_PORT"] && ENV["SELENIUM_HOST"].present?
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :remote_headless_chrome_with_media
  else
    driven_by :headless_chrome_with_media
  end

  # Return browser console logs (Selenium). Example usage in tests:
  #   logs = console_logs
  #   puts logs.map(&:message)
  def console_logs
    begin
      browser = page.driver.browser
      # Prefer the manage.logs interface if available
      if browser.respond_to?(:manage) && browser.manage.respond_to?(:logs)
        browser.manage.logs.get(:browser)
      elsif browser.respond_to?(:logs)
        # Some drivers expose logs directly
        browser.logs.get(:browser)
      else
        []
      end
    rescue StandardError => e
      Rails.logger.debug "Failed to fetch browser logs: #{e.class}: #{e.message}"
      []
    end
  end

  # Print browser console logs after each system test run to aid debugging.
  def teardown
    super
    begin
      logs = console_logs
      unless logs.nil? || logs.empty?
        puts "==== BROWSER CONSOLE LOGS ===="
        logs.each do |entry|
          # Selenium log entry may respond to .level, .message, .timestamp depending on driver
          msg = entry.respond_to?(:message) ? entry.message : entry.to_s
          puts msg
        end
        puts "==== END BROWSER CONSOLE LOGS ===="
      end
    rescue StandardError => e
      Rails.logger.debug "Failed to print browser logs in teardown: #{e.class}: #{e.message}"
    end
  end
end
