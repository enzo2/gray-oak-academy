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

  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :remote_headless_chrome_with_media
  else
    driven_by :headless_chrome_with_media
  end
end
