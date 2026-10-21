require "rails_helper"

RSpec.describe "API security controls", type: :request do
  it "filters secrets from nested request parameters used by application logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter({ "user" => { "password" => "secret", "password_confirmation" => "secret", "cpf" => "12345678909" }, "token" => "sensitive", "refresh_token" => "sensitive" })
    serialized = filtered.to_json
    expect(serialized).not_to include("secret", "sensitive", "12345678909")
  end

  it "rejects oversized JSON before processing credentials" do
    post "/api/v1/auth/login", params: { email: "absent@example.test", password: "a" * 40_000 }.to_json,
      headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(413)
    expect(parsed_body.fetch("error").fetch("code")).to eq("payload_too_large")
  end

  it "rejects form payloads on JSON-only authentication endpoints" do
    post "/api/v1/auth/login", params: { email: "absent@example.test", password: "incorrect-password" }
    expect(response).to have_http_status(:unsupported_media_type)
    expect(parsed_body.fetch("error").fetch("code")).to eq("unsupported_media_type")
  end

  it "limits repeated login attempts" do
    statuses = Array.new(30) do
      post "/api/v1/auth/login", params: { email: "missing@example.test", password: "incorrect-password" }, as: :json
      response.status
    end
    expect(statuses).to include(429)
    expect(response.body).not_to include("password_digest", "backtrace")
  end

  it "rejects malformed credential JSON before Rails parameter parsing can expose its content" do
    post "/api/v1/auth/login", params: '{"password":"credential-canary",',
      headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:bad_request)
    expect(parsed_body.fetch("error").fetch("code")).to eq("invalid_json")
    expect(response.body).not_to include("credential-canary", "backtrace")
  end

  it "rejects non-object JSON rather than crashing controller parameter handling" do
    post "/api/v1/auth/login", params: '["unexpected array"]',
      headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:bad_request)
    expect(parsed_body.fetch("error").fetch("code")).to eq("invalid_json")
  end
end
