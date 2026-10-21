ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("RSpec cannot run in production") if Rails.env.production?
require "rspec/rails"
require "active_job/test_helper"

ActiveRecord::Migration.maintain_test_schema!
Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include TestData
  config.include ActiveJob::TestHelper

  config.before do
    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.delivery_method = :test
    clear_enqueued_jobs
    clear_performed_jobs
    ActionMailer::Base.deliveries.clear
    if defined?(Rack::Attack)
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.reset!
    end
  end
end
