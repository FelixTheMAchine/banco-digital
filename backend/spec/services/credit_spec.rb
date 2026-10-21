require "rails_helper"

RSpec.describe "Transparent simulated credit" do
  it "calculates a known Price example and conserves every cent of principal" do
    result = Credit::Price.schedule(amount_cents: 100_000, monthly_rate: BigDecimal("0.02"), term_months: 12)
    expect(result[:installment_cents]).to eq(9456)
    expect(result[:total_cents]).to eq(113_470)
    expect(result[:schedule].sum { |row| row[:principal_cents] }).to eq(100_000)
    expect(result[:schedule].last).to include(payment_cents: 9454, balance_cents: 0)
    expect(result[:schedule].flat_map { |row| row.values_at(:principal_cents, :interest_cents, :payment_cents, :balance_cents) }).to all(be_a(Integer))
  end

  it "handles zero interest and adjusts the last cent without a negative balance" do
    result = Credit::Price.schedule(amount_cents: 100_001, monthly_rate: BigDecimal("0"), term_months: 12)
    expect(result[:total_cents]).to eq(100_001)
    expect(result[:schedule].sum { |row| row[:interest_cents] }).to eq(0)
    expect(result[:schedule].last[:balance_cents]).to eq(0)
  end

  it "rejects a floating monetary amount and invalid terms before computing" do
    expect { Credit::Price.schedule(amount_cents: 1000.5, monthly_rate: BigDecimal("0.02"), term_months: 12) }.to raise_error(FinancialProducts::Error)
    expect { Credit::Price.schedule(amount_cents: 1000, monthly_rate: BigDecimal("0.02"), term_months: 0) }.to raise_error(FinancialProducts::Error)
  end

  it "rejects borrowing when expenses consume the income, despite a high salary" do
    user = create_user(monthly_salary_cents: 2_000_000, other_income_cents: 0, monthly_expenses_cents: 2_100_000)
    result = Credit::Evaluator.call(user: user, amount_cents: 100_000, term_months: 12)
    expect(result[:eligible]).to be(false)
    expect(result[:available_income_cents]).to eq(0)
    expect(result[:estimated_limit_cents]).to eq(0)
    expect(result[:reasons].join).to include("despesas")
  end

  it "distinguishes a stock of debt from a declared monthly debt payment" do
    user = create_user(existing_debts_cents: 240_000)
    presumed = Credit::Evaluator.call(user: user, amount_cents: 100_000, term_months: 12)
    declared = Credit::Evaluator.call(user: user, amount_cents: 100_000, term_months: 12, monthly_debt_payment_cents: 100_000)
    expect(presumed[:available_income_cents] - declared[:available_income_cents]).to eq(90_000)
    expect(presumed[:assumptions].join).to include("estoque", "24 meses", "fictícias", "CET", "zero")
  end

  it "shows an internal explanatory score and no external credit report" do
    user = create_user
    result = Credit::Evaluator.call(user: user, amount_cents: 100_000, term_months: 12)
    expect(result[:eligible]).to be(true)
    expect(result[:score_factors].sum { |factor| factor[:points] }).to eq(result[:internal_score])
    expect(result[:assumptions].join).to include("Não há consulta", "não representa pontuação oficial")
    expect(result[:alternative_terms].size).to be >= 3
  end

  it "submits one application for an idempotent request and rejects key reuse with different data" do
    user = create_user
    args = { user: user, amount_cents: 100_000, term_months: 12, idempotency_key: "loan-request-123" }
    first = Credit::Applications.submit!(**args)
    second = Credit::Applications.submit!(**args)
    expect(second.id).to eq(first.id)
    expect(Loan.where(user_id: user.id).count).to eq(1)
    expect(first.loan_installments.sum(:principal_cents)).to eq(100_000)
    expect { Credit::Applications.submit!(**args.merge(amount_cents: 200_000)) }.to raise_error(FinancialProducts::Conflict)
  end

  it "keeps the original terms when an administrator activates a new rule version" do
    user = create_user
    admin = create_user(role: "admin")
    first = Credit::Applications.submit!(user: user, amount_cents: 100_000, term_months: 12, idempotency_key: "loan-rules-before")
    rule = CreditRule.activate!(config: { "monthly_rate" => "0.03" }, admin: admin)
    after = Credit::Evaluator.call(user: user, amount_cents: 100_000, term_months: 12)
    expect(after[:monthly_rate_percent]).to eq("3.0")
    expect(after[:rule_version]).to eq(rule.version)
    expect(first.reload.monthly_rate).to eq(BigDecimal("0.019"))
    expect(first.rule_version).to eq(0)
  end

  it "rejects rule changes from a customer and out-of-bounds rule values" do
    user = create_user
    expect { CreditRule.activate!(config: {}, admin: user) }.to raise_error(FinancialProducts::Error)
    admin = create_user(role: "admin")
    expect { CreditRule.activate!(config: { "monthly_rate" => "0.99" }, admin: admin) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(CreditRule.where(active: true)).not_to exist
  end

  it "records an administrative review and resolves the appeal without moving account money" do
    user = create_user(monthly_salary_cents: 0, other_income_cents: 0)
    admin = create_user(role: "admin")
    loan = Credit::Applications.submit!(user: user, amount_cents: 100_000, term_months: 12, idempotency_key: "loan-appeal-demo")
    expect(loan.status).to eq("rejected")
    appeal = Credit::Applications.appeal!(loan: loan, user: user, reason: "Solicito revisão dos dados declarados.")
    expect(loan.reload.status).to eq("pending_review")
    balances_before = Account.sum(:available_cents)
    Credit::Applications.review!(loan: loan, admin: admin, decision: "reject", reason: "Renda disponível insuficiente na revisão simulada.")
    expect(loan.reload.status).to eq("reviewed_rejected")
    expect(appeal.reload.status).to eq("reviewed")
    expect(appeal.outcome["decision"]).to eq("reject")
    expect(Account.sum(:available_cents)).to eq(balances_before)
  end

  it "rolls back the review when its audit record cannot be persisted" do
    user = create_user
    admin = create_user(role: "admin")
    loan = Credit::Applications.submit!(user: user, amount_cents: 100_000, term_months: 12, idempotency_key: "loan-review-rollback")
    allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "simulated persistence failure")
    expect { Credit::Applications.review!(loan: loan, admin: admin, decision: "approve", reason: "Análise demonstrativa dentro das regras.") }.to raise_error(ActiveRecord::StatementInvalid)
    expect(loan.reload.status).to eq("pending_review")
    expect(loan.reviewed_at).to be_nil
  end
end
