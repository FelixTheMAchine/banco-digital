require "rails_helper"

RSpec.describe RateLimitAvailability do
  it "fails closed with a retryable JSON response and never exposes Redis connection details" do
    [Redis::BaseError, RedisClient::Error].each do |error_class|
      app = described_class.new(->(_env) { raise error_class, "private-credential-canary" })
      status, headers, body = app.call({})
      expect(status).to eq(503)
      expect(headers).to include("content-type" => "application/json", "cache-control" => "no-store", "retry-after" => "30")
      expect(JSON.parse(body.join).fetch("error").fetch("code")).to eq("service_unavailable")
      expect(body.join).not_to include("private-credential-canary", "backtrace")
    end
  end
end
