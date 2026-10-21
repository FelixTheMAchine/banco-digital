require "rails_helper"

RSpec.describe "Administrative authorization", type: :request do
  def admin_tokens(user, verified_at: Time.current)
    Auth::SessionService.issue!(user: user, mfa_verified_at: verified_at).stringify_keys
  end

  it "denies ordinary customers access to administration and spreadsheets" do
    user = create_user
    tokens = login_as(user)
    get "/api/v1/admin/overview", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/admin/exports.xlsx", params: { kind: "accounts" }, headers: bearer_headers(tokens)
    expect(response).to have_http_status(:forbidden)
    expect(AuditLog.where(action: "admin.export.accounts")).not_to exist
  end

  it "requires an administrator to enroll MFA" do
    user = create_user(role: "admin")
    tokens = login_as(user)
    get "/api/v1/admin/overview", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:forbidden)
    expect(parsed_body.dig("error", "code")).to eq("mfa_required")
  end

  it "requires fresh step-up even when the administrative role is valid" do
    user = create_user(role: "admin", mfa_secret: ROTP::Base32.random_base32, mfa_enabled_at: Time.current)
    tokens = admin_tokens(user, verified_at: 6.minutes.ago)
    get "/api/v1/admin/audit_logs", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:forbidden)
    expect(parsed_body.dig("error", "code")).to eq("mfa_step_up_required")
  end

  it "allows a recently verified administrator to view the simulated overview" do
    user = create_user(role: "admin", mfa_secret: ROTP::Base32.random_base32, mfa_enabled_at: Time.current)
    tokens = admin_tokens(user)
    get "/api/v1/admin/overview", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:ok)
    expect(parsed_body.dig("overview", "simulation")).to be(true)
  end

  it "rejects unknown financial-rule keys without changing settings" do
    user = create_user(role: "admin", mfa_secret: ROTP::Base32.random_base32, mfa_enabled_at: Time.current)
    tokens = admin_tokens(user)
    expect do
      patch "/api/v1/admin/financial_rules", params: { rules: { "users.role" => 99 } }, headers: bearer_headers(tokens), as: :json
    end.not_to change(FinancialRule, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
