require "rails_helper"

RSpec.describe "MFA authentication", type: :request do
  it "requires a second factor after a correct password and rejects a reused code" do
    secret = ROTP::Base32.random_base32
    user = create_user(mfa_secret: secret, mfa_enabled_at: Time.current)
    post "/api/v1/auth/login", params: { email: user.email, password: "Ficticia-Forte-9347!" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(parsed_body.dig("error", "code")).to eq("mfa_required")
    expect(user.auth_sessions.count).to eq(0)
    code = ROTP::TOTP.new(secret).now
    post "/api/v1/auth/login", params: { email: user.email, password: "Ficticia-Forte-9347!", otp_code: code }, as: :json
    expect(response).to have_http_status(:ok)
    expect(user.auth_sessions.last.mfa_verified_at).to be_present
    post "/api/v1/auth/login", params: { email: user.email, password: "Ficticia-Forte-9347!", otp_code: code }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(user.auth_sessions.count).to eq(1)
  end

  it "does not accept an OTP without the correct password" do
    secret = ROTP::Base32.random_base32
    user = create_user(mfa_secret: secret, mfa_enabled_at: Time.current)
    post "/api/v1/auth/login", params: { email: user.email, password: "wrong-password", otp_code: ROTP::TOTP.new(secret).now }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(user.auth_sessions).not_to exist
  end

  it "keeps step-up freshness unchanged when refresh tokens rotate" do
    user = create_user(mfa_secret: ROTP::Base32.random_base32, mfa_enabled_at: Time.current)
    verified = 6.minutes.ago.change(usec: 0)
    tokens = Auth::SessionService.issue!(user: user, mfa_verified_at: verified)
    post "/api/v1/auth/refresh", params: { refresh_token: tokens.fetch(:refresh_token) }, as: :json
    expect(response).to have_http_status(:ok)
    new_session = user.auth_sessions.where(revoked_at: nil).first
    expect(new_session.mfa_verified_at.to_i).to eq(verified.to_i)
  end
end
