require "rails_helper"

RSpec.describe "Financial product API ownership", type: :request do
  it "requires authentication before simulating or listing product data" do
    get "/api/v1/loans"
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/investment_simulations", params: { initial_amount_cents: 1000, monthly_contribution_cents: 0, months: 12, annual_rate_percent: "10" }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "provides a reproducible loan simulation and rejects manipulated fractional amounts" do
    user = create_user
    tokens = login_as(user)
    post "/api/v1/loan_simulations", params: { amount_cents: 100_000, term_months: 12 }, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:ok)
    expect(parsed_body["simulation"]).to include("eligible", "schedule", "estimated_cet_annual_percent", "assumptions")
    post "/api/v1/loan_simulations", params: { amount_cents: 100_000.5, term_months: 12 }, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "isolates loan details and appeals between customers" do
    owner = create_user
    foreign = create_user
    loan = Credit::Applications.submit!(user: owner, amount_cents: 100_000, term_months: 12, idempotency_key: "foreign-loan-access")
    tokens = login_as(foreign)
    get "/api/v1/loans/#{loan.id}", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:not_found)
    post "/api/v1/loans/#{loan.id}/appeals", params: { reason: "Tentativa de acesso a outro cliente." }, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:not_found)
    expect(loan.loan_appeals).not_to exist
  end

  it "isolates saved investment simulations between customers" do
    owner = create_user
    foreign = create_user
    simulation = Investments::Simulator.save!(user: owner, initial_amount_cents: 1000, monthly_contribution_cents: 0, months: 12, annual_rate_percent: "10")
    tokens = login_as(foreign)
    get "/api/v1/investment_simulations/#{simulation.id}", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:not_found)
    get "/api/v1/investment_simulations", headers: bearer_headers(tokens)
    expect(response).to have_http_status(:ok)
    expect(parsed_body.fetch("investment_simulations")).to eq([])
  end

  it "limits goal updates to the authenticated owner and preserves integer targets" do
    owner = create_user
    foreign = create_user
    goal = FinancialGoal.create!(user: owner, name: "Reserva de emergência", target_cents: 100_000, target_date: 1.year.from_now.to_date)
    tokens = login_as(foreign)
    patch "/api/v1/financial_goals/#{goal.id}", params: { financial_goal: { target_cents: 0 } }, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:not_found)
    expect(goal.reload.target_cents).to eq(100_000)
  end

  it "rejects a malformed investor questionnaire instead of raising a server error" do
    user = create_user
    tokens = login_as(user)
    post "/api/v1/investment_profile", params: { answers: ["invalid"] }, headers: bearer_headers(tokens), as: :json
    expect(response).to have_http_status(:bad_request)
  end
end
