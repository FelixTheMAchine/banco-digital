require "rails_helper"

RSpec.describe "Banking API ownership and receipts", type: :request do
  it "opens an account and produces a simulation receipt after a deposit" do
    user = create_user
    tokens = login_as(user)
    post "/api/v1/account", params: {}, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:created)
    number = parsed_body.fetch("account").fetch("number")
    key = SecureRandom.uuid
    post "/api/v1/account/deposits", params: { amount_cents: 1_000 },
      headers: bearer_headers(tokens).merge("Idempotency-Key" => key), as: :json
    expect(response).to have_http_status(:created)
    transaction_id = parsed_body.fetch("transaction").fetch("id")
    get "/api/v1/transactions/#{transaction_id}/receipt", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:ok)
    expect(parsed_body.fetch("receipt")).to include("simulation" => true, "account_number" => number, "currency" => "BRL")
    get "/api/v1/dashboard", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:ok)
    expect(parsed_body.fetch("account").fetch("available_cents")).to eq(1_000)
    expect(parsed_body.fetch("month_income_cents")).to eq(1_000)
  end

  it "requires an idempotency key and integer cents at the API boundary" do
    user = create_user
    account = Banking::Opening.open!(user: user)
    tokens = login_as(user)
    post "/api/v1/account/deposits", params: { amount_cents: 100 }, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:bad_request)
    post "/api/v1/account/deposits", params: { amount_cents: 0.5 },
      headers: bearer_headers(tokens).merge("Idempotency-Key" => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.available_cents).to eq(0)
  end

  it "prevents access to another customer's statement, receipt or notification" do
    user = create_user
    outsider = create_user
    account = Banking::Opening.open!(user: user)
    Banking::Opening.open!(user: outsider)
    original = Banking::Operations.deposit!(user: user, amount_cents: 100, idempotency_key: SecureRandom.uuid)
    notification = Notification.find_by!(user_id: user.id)
    tokens = login_as(outsider)
    get "/api/v1/transactions/#{original.id}", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:not_found)
    get "/api/v1/transactions/#{original.id}/receipt", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:not_found)
    patch "/api/v1/notifications/#{notification.id}/read", params: {}, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:not_found)
    get "/api/v1/transactions", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:ok)
    expect(parsed_body.fetch("transactions")).to be_empty
    expect(account.reload.available_cents).to eq(100)
  end

  it "filters the statement and returns controlled errors for invalid dates" do
    user = create_user
    Banking::Opening.open!(user: user)
    Banking::Operations.deposit!(user: user, amount_cents: 100, idempotency_key: SecureRandom.uuid)
    Banking::Operations.withdraw!(user: user, amount_cents: 20, idempotency_key: SecureRandom.uuid)
    tokens = login_as(user)
    get "/api/v1/transactions", params: { type: "withdrawal" }, headers: bearer_headers(tokens)
    expect(response).to have_http_status(:ok)
    expect(parsed_body.fetch("transactions").map { |row| row.fetch("kind") }).to eq(["withdrawal"])
    get "/api/v1/transactions", params: { from: "not-a-date" }, headers: bearer_headers(tokens)
    expect(response).to have_http_status(:bad_request)
    expect(parsed_body.fetch("error").fetch("code")).to eq("invalid_filter")
  end

  it "closes only the authenticated customer's empty account" do
    user = create_user
    own = Banking::Opening.open!(user: user)
    outsider = Banking::Opening.open!(user: create_user)
    tokens = login_as(user)
    post "/api/v1/account/close", params: { user_id: outsider.user_id, account_id: outsider.id },
      headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:ok)
    expect(parsed_body.fetch("account")).to include("id" => own.id, "status" => "closed")
    expect(outsider.reload.status).to eq("active")
    post "/api/v1/account/deposits", params: { amount_cents: 100 },
      headers: bearer_headers(tokens).merge("Idempotency-Key" => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
