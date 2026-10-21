require "rails_helper"

RSpec.describe "Customer registration", type: :request do
  it "creates an unverified customer and queues a verification message without tokens in JSON" do
    attributes = user_attributes
    expect do
      post "/api/v1/auth/register", params: { user: attributes }, as: :json
    end.to change(User, :count).by(1)
    expect(response).to have_http_status(:created)
    user = User.find_by!(email: attributes.fetch(:email))
    expect(user.email_verified_at).to be_nil
    expect(enqueued_jobs).not_to be_empty
    expect(enqueued_jobs.map { |job| job.fetch(:args) }.to_json).not_to match(/[0-9a-f]{64}/)
    expect(parsed_body.fetch("user").fetch("email_verified")).to be(false)
    expect(response.body).not_to match(/password_digest|access_token|refresh_token|token_digest/)
  end

  it "validates registration and rolls back invalid records" do
    expect do
      post "/api/v1/auth/register", params: { user: user_attributes(cpf: "11111111111") }, as: :json
    end.not_to change(User, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(parsed_body.fetch("error")).to include("code", "message")
  end

  it "does not allow registration to assign an administrative role or verified status" do
    attributes = user_attributes
    post "/api/v1/auth/register", params: { user: attributes.merge(role: "admin", email_verified_at: Time.current, status: "blocked") }, as: :json
    expect(response).to have_http_status(:created)
    user = User.find_by!(email: attributes.fetch(:email))
    expect(user.role).to eq(User.new.role)
    expect(user.status).to eq("active")
    expect(user.email_verified_at).to be_nil
  end

  ["unexpected text", ["unexpected array"]].each do |malformed_user|
    it "rejects a #{malformed_user.class.name} user payload with a controlled client error" do
      expect do
        post "/api/v1/auth/register", params: { user: malformed_user }, as: :json
      end.not_to change(User, :count)
      expect(response).to have_http_status(:bad_request)
      expect(parsed_body.fetch("error").fetch("code")).to eq("invalid_request")
    end
  end

  it "requires an explicit monthly salary declaration instead of silently substituting zero" do
    attributes = user_attributes.except(:monthly_salary_cents)
    expect do
      post "/api/v1/auth/register", params: { user: attributes }, as: :json
    end.not_to change(User, :count)
    expect(response).to have_http_status(:bad_request)
  end

  it "returns a controlled validation response for an existing email" do
    user = create_user
    post "/api/v1/auth/register", params: { user: user_attributes(email: user.email) }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include("PG::", "SELECT", "password_digest")
  end
end
