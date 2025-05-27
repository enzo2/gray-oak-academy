require "test_helper"

module SystemTestAuthenticationHelpers
  def sign_in(user, password: "password")
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_on "Log in"
    # If login fails, print the page for debugging
    unless page.has_no_text?("Invalid Email or password.")
      puts page.body
    end
  end
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include SystemTestAuthenticationHelpers

  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  end
end
