Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = false
  config.action_dispatch.show_exceptions = :none
  config.active_job.queue_adapter = :test
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
  config.action_mailer.logger = nil
  config.active_job.logger = nil
  config.active_record.logger = nil
  config.active_record.dump_schema_after_migration = false
  config.cache_store = :null_store
  config.secret_key_base = "test-only-" + "1" * 80
  config.active_record.encryption.primary_key = "test-primary-key-" + "a" * 32
  config.active_record.encryption.deterministic_key = "test-deterministic-" + "b" * 32
  config.active_record.encryption.key_derivation_salt = "test-derivation-" + "c" * 32
  config.hosts.clear
end
