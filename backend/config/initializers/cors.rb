Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("APP_ORIGINS", "http://localhost:3000").split(",").map(&:strip))
    resource "/api/*", headers: %w[Authorization Content-Type Idempotency-Key],
             methods: %i[get post patch delete options], credentials: false, max_age: 600
  end
end
