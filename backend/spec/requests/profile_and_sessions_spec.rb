require "rails_helper"

RSpec.describe "Customer data and session ownership", type: :request do
  it "updates only the authenticated profile and allowed financial declarations" do
    user = create_user
    another_user = create_user
    tokens = login_as(user)
    patch "/api/v1/me", params: { user: { full_name: "Nome Atualizado", monthly_salary_cents: 700_000, id: another_user.id, role: "admin", email: "changed@example.test", cpf: another_user.cpf } }, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:ok)
    expect(user.reload.full_name).to eq("Nome Atualizado")
    expect(user.monthly_salary_cents).to eq(700_000)
    expect(user.role).to eq(User.new.role)
    expect(user.email).not_to eq("changed@example.test")
    expect(another_user.reload.full_name).to eq("Cliente de Teste")
  end

  ["unexpected text", ["unexpected array"]].each do |malformed_user|
    it "rejects a #{malformed_user.class.name} profile payload without modifying personal data" do
      user = create_user
      tokens = login_as(user)
      patch "/api/v1/me", params: { user: malformed_user }, headers: bearer_headers(tokens), as: :json
      expect(response).to have_http_status(:bad_request)
      expect(parsed_body.fetch("error").fetch("code")).to eq("invalid_request")
      expect(user.reload.full_name).to eq("Cliente de Teste")
    end
  end

  it "rejects fractional money declarations through the API without modifying stored values" do
    user = create_user
    tokens = login_as(user)
    patch "/api/v1/me", params: { user: { monthly_salary_cents: 55.5 } }, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.monthly_salary_cents).to eq(600_000)
  end

  it "lists only the current customer's sessions without credential digests" do
    user = create_user
    first = login_as(user)
    login_as(user)
    another_user = create_user
    login_as(another_user)
    get "/api/v1/sessions", headers: bearer_headers(first)
    expect(response).to have_http_status(:ok)
    sessions = parsed_body.fetch("sessions")
    expect(sessions.size).to eq(2)
    expect(sessions.count { |session| session.fetch("current") }).to eq(1)
    expect(sessions.map { |session| session.fetch("id") }).to match_array(user.auth_sessions.pluck(:id))
    expect(response.body).not_to match(/access_digest|refresh_digest|access_token|refresh_token/)
  end

  it "prevents revocation of another customer's session" do
    user = create_user
    tokens = login_as(user)
    another_user = create_user
    other_tokens = login_as(another_user)
    foreign_session = another_user.auth_sessions.first
    delete "/api/v1/sessions/#{foreign_session.id}", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:not_found)
    expect(foreign_session.reload.revoked_at).to be_nil
    get "/api/v1/me", headers: bearer_headers(other_tokens)
    expect(response).to have_http_status(:ok)
  end

  it "revokes an owned session while preserving the requesting session" do
    user = create_user
    first = login_as(user)
    second = login_as(user)
    second_session = user.auth_sessions.order(:created_at).last
    delete "/api/v1/sessions/#{second_session.id}", headers: bearer_headers(first)
    expect(response).to have_http_status(:no_content)
    get "/api/v1/me", headers: bearer_headers(second)
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/me", headers: bearer_headers(first)
    expect(response).to have_http_status(:ok)
  end

  it "deactivates the profile, revokes all sessions and prevents new login" do
    user = create_user
    first = login_as(user)
    second = login_as(user)
    delete "/api/v1/me", headers: bearer_headers(first)
    expect(response).to have_http_status(:no_content)
    expect(user.reload.status).not_to eq("active")
    expect(user.auth_sessions.where(revoked_at: nil)).not_to exist
    get "/api/v1/me", headers: bearer_headers(second)
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/auth/login", params: { email: user.email, password: "Ficticia-Forte-9347!" }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
