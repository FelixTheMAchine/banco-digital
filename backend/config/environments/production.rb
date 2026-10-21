Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = true
  config.ssl_options = { hsts: { expires: 1.year, subdomains: true } }
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.active_record.logger = nil
  config.active_job.logger = nil
  config.action_mailer.logger = nil
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("SMTP_ADDRESS"), port: ENV.fetch("SMTP_PORT", "587").to_i,
    user_name: ENV.fetch("SMTP_USERNAME"), password: ENV.fetch("SMTP_PASSWORD"),
    authentication: :plain, enable_starttls: true, openssl_verify_mode: "peer"
  }
  config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL") }
  config.hosts = ENV.fetch("APP_HOSTS").split(",").map(&:strip)
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE")
  raise "SECRET_KEY_BASE precisa ser aleatório e ter pelo menos 64 caracteres" if config.secret_key_base.length < 64 || config.secret_key_base.include?("change-me")
  raise "APP_FRONTEND_URL deve usar HTTPS" unless ENV.fetch("APP_FRONTEND_URL").start_with?("https://")
  %w[primary_key deterministic_key key_derivation_salt].each do |key|
    value = ENV.fetch("AR_ENCRYPTION_#{key.upcase}")
    raise "Chave de criptografia inválida" if value.length < 32
    config.active_record.encryption.public_send("#{key}=", value)
  end
end
