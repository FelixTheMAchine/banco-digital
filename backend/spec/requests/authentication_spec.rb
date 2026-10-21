require "rails_helper"

RSpec.describe "Authentication and session rotation", type: :request do
  it "issues short-lived opaque tokens and stores only their digests" do
    user = create_user
    tokens = login_as(user)
    expect(tokens).to include("token_type" => "Bearer", "expires_in" => 900)
    session = user.auth_sessions.order(:created_at).last
    expect(session.access_digest).not_to eq(tokens.fetch("access_token"))
    expect(session.refresh_digest).not_to eq(tokens.fetch("refresh_token"))
    get "/api/v1/me", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:ok)
    expect(parsed_body.fetch("user").fetch("id")).to eq(user.id)
  end

  it "uses the same failure response for unknown accounts, invalid passwords and unverified users" do
    user = create_user(email_verified_at: nil)
    bodies = [
      { email: "absent@example.test", password: "incorrect-password" },
      { email: user.email, password: "incorrect-password" },
      { email: user.email, password: "Ficticia-Forte-9347!" }
    ].map do |params|
      post "/api/v1/auth/login", params: params, as: :json
      expect(response).to have_http_status(:unauthorized)
      parsed_body
    end
    expect(bodies.uniq.size).to eq(1)
  end

  it "rotates both tokens and rejects the previous access token" do
    user = create_user
    previous = login_as(user)
    post "/api/v1/auth/refresh", params: { refresh_token: previous.fetch("refresh_token") }, as: :json
    expect(response).to have_http_status(:ok)
    renewed = parsed_body
    expect(renewed.fetch("access_token")).not_to eq(previous.fetch("access_token"))
    expect(renewed.fetch("refresh_token")).not_to eq(previous.fetch("refresh_token"))
    get "/api/v1/me", headers: bearer_headers(previous)
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/me", headers: bearer_headers(renewed)
    expect(response).to have_http_status(:ok)
  end

  it "revokes the rotated family when a consumed refresh token is replayed" do
    user = create_user
    original = login_as(user)
    post "/api/v1/auth/refresh", params: { refresh_token: original.fetch("refresh_token") }, as: :json
    renewed = parsed_body
    post "/api/v1/auth/refresh", params: { refresh_token: original.fetch("refresh_token") }, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/me", headers: bearer_headers(renewed)
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/auth/refresh", params: { refresh_token: renewed.fetch("refresh_token") }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects expired access tokens while allowing a still-valid refresh" do
    user = create_user
    tokens = login_as(user)
    user.auth_sessions.update_all(access_expires_at: 1.minute.ago)
    get "/api/v1/me", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/auth/refresh", params: { refresh_token: tokens.fetch("refresh_token") }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "rejects expired refresh tokens" do
    user = create_user
    tokens = login_as(user)
    user.auth_sessions.update_all(access_expires_at: 2.minutes.ago, expires_at: 1.minute.ago)
    post "/api/v1/auth/refresh", params: { refresh_token: tokens.fetch("refresh_token") }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "invalidates access and refresh credentials on logout" do
    user = create_user
    tokens = login_as(user)
    delete "/api/v1/auth/logout", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:no_content)
    get "/api/v1/me", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/auth/refresh", params: { refresh_token: tokens.fetch("refresh_token") }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "requires authentication for personal data" do
    get "/api/v1/me"
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/me", headers: { "Authorization" => "Bearer fabricated-token" }
    expect(response).to have_http_status(:unauthorized)
  end
end
