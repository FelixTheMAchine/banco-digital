Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = false
  config.active_record.logger = nil # Não registrar binds contendo dados cadastrais.
  config.action_mailer.delivery_method = :file
  config.action_mailer.file_settings = { location: Rails.root.join("tmp/mails") }
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.logger = nil # Mensagens contêm links de uso único.
  config.active_job.logger = nil
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
  config.hosts = ENV.fetch("APP_HOSTS", "localhost,127.0.0.1,api,10.0.2.2").split(",").map(&:strip)
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") { "development-only-" + "0" * 80 }
  %w[primary_key deterministic_key key_derivation_salt].each do |key|
    config.active_record.encryption.public_send("#{key}=", ENV.fetch("AR_ENCRYPTION_#{key.upcase}") {
      Digest::SHA256.hexdigest("#{config.secret_key_base}:#{key}")
    })
  end
end
