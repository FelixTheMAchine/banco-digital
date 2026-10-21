require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "rails/test_unit/railtie"
Bundler.require(*Rails.groups)

module BancoDigital
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
    config.time_zone = "UTC"
    config.active_record.schema_format = :sql
    config.active_job.queue_adapter = :sidekiq
    config.autoload_lib(ignore: %w[assets tasks])
    config.action_dispatch.rescue_responses["ActionController::ParameterMissing"] = :bad_request
    config.generators do |g|
      g.test_framework :rspec
      g.orm :active_record, primary_key_type: :uuid
    end
    config.log_tags = [:request_id]
    config.filter_parameters += %i[password password_confirmation token access_token refresh_token
                                  authorization cpf birth_date email phone address full_name
                                  monthly_salary_cents other_income_cents monthly_expenses_cents
                                  existing_debts_cents]
    config.filter_parameters += %i[otp_code code recovery_code recovery_codes secret provisioning_uri
                                   mfa_secret mfa_pending_secret mfa_recovery_digests]
    config.filter_parameters += %i[reason review_reason answers goal title description config]
    config.action_dispatch.default_headers.merge!(
      "X-Content-Type-Options" => "nosniff",
      "X-Frame-Options" => "DENY",
      "Referrer-Policy" => "no-referrer",
      "Permissions-Policy" => "camera=(), microphone=(), geolocation=()",
      "Content-Security-Policy" => "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
    )
  end
end
