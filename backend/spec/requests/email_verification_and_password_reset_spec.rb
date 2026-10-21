require "rails_helper"

RSpec.describe "Purpose-limited recovery credentials", type: :request do
  it "does not reveal account existence when requesting recovery or verification" do
    user = create_user(email_verified_at: nil)
    %w[email_verifications password_resets].each do |endpoint|
      bodies = [user.email, "absent@example.test"].map do |email|
        post "/api/v1/auth/#{endpoint}", params: { email: email }, as: :json
        expect(response).to have_http_status(:accepted)
        parsed_body
      end
      expect(bodies.uniq.size).to eq(1)
      expect(bodies.first.keys).to eq(["message"])
    end
  end

  it "verifies email once with a valid token and then permits login" do
    user = create_user(email_verified_at: nil)
    token = Auth::PurposeTokenService.issue!(user: user, purpose: "email_verification")
    patch "/api/v1/auth/email_verifications", params: { token: token }, as: :json
    expect(response).to have_http_status(:ok)
    expect(user.reload.email_verified_at).to be_present
    patch "/api/v1/auth/email_verifications", params: { token: token }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    login_as(user)
    expect(response).to have_http_status(:ok)
  end

  it "does not accept expired verification credentials" do
    user = create_user(email_verified_at: nil)
    token = Auth::PurposeTokenService.issue!(user: user, purpose: "email_verification")
    user.purpose_tokens.update_all(expires_at: 1.minute.ago)
    patch "/api/v1/auth/email_verifications", params: { token: token }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.email_verified_at).to be_nil
  end

  it "rejects a password-reset credential presented as email verification" do
    user = create_user(email_verified_at: nil)
    token = Auth::PurposeTokenService.issue!(user: user, purpose: "password_reset")
    patch "/api/v1/auth/email_verifications", params: { token: token }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.email_verified_at).to be_nil
  end

  it "changes the password, revokes sessions and consumes the recovery credential" do
    user = create_user
    sessions = [login_as(user), login_as(user)]
    token = Auth::PurposeTokenService.issue!(user: user, purpose: "password_reset")
    replacement_password = "Outra-Ficticia-Forte-9876!"
    patch "/api/v1/auth/password_resets", params: { token: token, password: replacement_password, password_confirmation: replacement_password }, as: :json
    expect(response).to have_http_status(:ok)
    expect(user.reload.authenticate(replacement_password)).to be_truthy
    expect(user.authenticate("Ficticia-Forte-9347!")).to be_falsey
    sessions.each do |tokens|
      get "/api/v1/me", headers: bearer_headers(tokens)
      expect(response).to have_http_status(:unauthorized)
      post "/api/v1/auth/refresh", params: { refresh_token: tokens.fetch("refresh_token") }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
    patch "/api/v1/auth/password_resets", params: { token: token, password: replacement_password, password_confirmation: replacement_password }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    login_as(user, password: replacement_password)
  end

  it "rolls back an invalid password without consuming a valid recovery token" do
    user = create_user
    token = Auth::PurposeTokenService.issue!(user: user, purpose: "password_reset")
    patch "/api/v1/auth/password_resets", params: { token: token, password: "short", password_confirmation: "short" }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.authenticate("Ficticia-Forte-9347!")).to be_truthy
    replacement_password = "Outra-Ficticia-Forte-9876!"
    patch "/api/v1/auth/password_resets", params: { token: token, password: replacement_password, password_confirmation: replacement_password }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "does not authenticate an opaque email verification credential as an access token" do
    user = create_user
    token = Auth::PurposeTokenService.issue!(user: user, purpose: "email_verification")
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:unauthorized)
  end
end
