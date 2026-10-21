Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
  # Sidekiq's default error context includes job arguments; these contain e-mails.
  config.error_handlers.clear
  config.error_handlers << lambda do |error, _context, _config|
    Sidekiq.logger.error("job_failed class=#{error.class.name}")
  end
end
Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
