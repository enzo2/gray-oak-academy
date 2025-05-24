class Rack::Attack
  throttle("req/ip", limit: 500, period: 5.minutes) do |req|
    req.ip # unless req.path.start_with?('/assets')
  end

  # Limit sign up attempts by IP address
  throttle("registrations/ip", limit: 10, period: 5.minutes) do |req|
    if req.path == "/users" && req.post?
      req.ip
    end
  end
end
