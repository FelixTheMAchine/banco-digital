require Rails.root.join("lib/request_limits")
require Rails.root.join("lib/rate_limit_availability")
Rails.application.config.middleware.insert_before Rack::Attack, RequestLimits
Rails.application.config.middleware.insert_before Rack::Attack, RateLimitAvailability
