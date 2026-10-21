require "rails_helper"

RSpec.describe "Educational investment decisions" do
  def answers(overrides = {})
    { "risk_tolerance" => "high", "knowledge" => "advanced", "horizon_months" => 120,
      "liquidity_need" => "low", "emergency_reserve_cents" => 2_000_000,
      "goal" => "Planejamento de longo prazo", "monthly_contribution_cents" => 20_000 }.merge(overrides)
  end

  it "puts the emergency reserve before a high declared appetite for risk" do
    user = create_user
    result = Investments::Profiler.call(user: user, answers: answers("emergency_reserve_cents" => 0))
    expect(result[:profile]).to eq("conservative")
    expect(result[:emergency_target_cents]).to eq(user.monthly_expenses_cents * 6)
    expect(result[:recommendations].map { |item| item[:asset_class] }).to eq(["Tesouro Selic"])
    expect(result[:warnings].join).to include("reserva de emergência")
  end

  it "restricts a short horizon or high liquidity need even for a wealthy customer" do
    user = create_user(monthly_salary_cents: 3_000_000)
    result = Investments::Profiler.call(user: user, answers: answers("liquidity_need" => "high"))
    expect(result[:profile]).to eq("conservative")
    expect(result[:recommendations].sum { |item| item[:allocation_percent] }).to eq(100)
  end

  it "creates a diversified aggressive scenario only with compatible reserve, knowledge and horizon" do
    user = create_user
    result = Investments::Profiler.call(user: user, answers: answers)
    expect(result[:profile]).to eq("aggressive")
    expect(result[:recommendations].sum { |item| item[:allocation_percent] }).to eq(100)
    expect(result[:recommendations].map { |item| item[:asset_class] }).to include("ETFs", "Ações", "Tesouro IPCA+")
    expect(result[:recommendations]).to all(include(:reason, :risk, :liquidity))
  end

  it "does not suggest available capital or affordable contributions when income is exhausted" do
    user = create_user(monthly_salary_cents: 0, other_income_cents: 0)
    result = Investments::Profiler.call(user: user, answers: answers)
    expect(result[:available_to_invest_cents]).to eq(0)
    expect(result[:profile]).to eq("conservative")
    expect(result[:warnings].join).to include("excede a renda disponível", "Não há renda")
  end

  it "saves suitability and updates the declared investor classification atomically" do
    user = create_user
    profile = Investments::Profiler.save!(user: user, answers: answers)
    expect(user.reload.investor_profile).to eq(profile.profile)
    expect(profile.public_json["disclaimer"]).to include("taxas fictícias", "perdas")
    expect(InvestmentProfile.where(user_id: user.id).count).to eq(1)
    Investments::Profiler.save!(user: user, answers: answers("risk_tolerance" => "low"))
    expect(InvestmentProfile.where(user_id: user.id).count).to eq(1)
  end

  it "lists all eight classes with fictional rates and concrete risk information" do
    products = Investments::Products.list
    expect(products.size).to eq(8)
    expect(products).to all(include(:annual_rate_percent, :risk, :liquidity, :description))
    expect(products.map { |product| product[:asset_class] }).to include("LCI/LCA", "Fundos imobiliários", "Ações")
  end

  it "conserves contributions exactly with a zero return scenario" do
    result = Investments::Simulator.call(initial_amount_cents: 10_000, monthly_contribution_cents: 1000, months: 12, annual_rate_percent: "0")
    expect(result).to include(final_cents: 22_000, contributed_cents: 22_000, earnings_cents: 0)
    expect(result[:projection].size).to eq(13)
    expect(result[:projection].last[:balance_cents]).to eq(22_000)
    expect(result[:scenarios].map { |item| item[:name] }).to eq(["adverso", "base", "favorável"])
  end

  it "shows losses for a negative scenario and never promises a positive return" do
    result = Investments::Simulator.call(initial_amount_cents: 100_000, monthly_contribution_cents: 0, months: 12, annual_rate_percent: "-10")
    expect(result[:final_cents]).to be < 100_000
    expect(result[:earnings_cents]).to be < 0
    expect(result[:projection].map { |row| row[:balance_cents] }).to all(be_a(Integer))
  end

  it "rejects floats, excessive horizons and projections beyond safe cent representation" do
    arguments = { initial_amount_cents: 100_000, monthly_contribution_cents: 0, months: 12, annual_rate_percent: "10" }
    expect { Investments::Simulator.call(**arguments.merge(initial_amount_cents: 100.5)) }.to raise_error(FinancialProducts::Error)
    expect { Investments::Simulator.call(**arguments.merge(annual_rate_percent: 10.0)) }.to raise_error(FinancialProducts::Error)
    expect { Investments::Simulator.call(**arguments.merge(months: 601)) }.to raise_error(FinancialProducts::Error)
    expect { Investments::Simulator.call(initial_amount_cents: 100_000_000, monthly_contribution_cents: 100_000_000, months: 600, annual_rate_percent: "50") }.to raise_error(FinancialProducts::Error)
  end

  it "simulates each portfolio asset separately while preserving indivisible contribution cents" do
    result = Investments::PortfolioSimulator.call(initial_amount_cents: 10_001, monthly_contribution_cents: 1001, months: 12,
      allocations: [{ "product_id" => "tesouro-selic", "allocation_percent" => 55 }, { "product_id" => "etf", "allocation_percent" => 45 }])
    assets = result[:portfolio][:allocations]
    expect(assets.sum { |asset| asset[:initial_cents] }).to eq(10_001)
    expect(assets.sum { |asset| asset[:monthly_contribution_cents] }).to eq(1001)
    expect(assets.sum { |asset| asset[:final_cents] }).to eq(result[:final_cents])
    expect(result[:contributed_cents]).to eq(22_013)
    expect(result[:scenarios].size).to eq(3)
  end

  it "rejects unbalanced, repeated and unknown portfolio asset allocations" do
    args = { initial_amount_cents: 1000, monthly_contribution_cents: 0, months: 12 }
    expect { Investments::PortfolioSimulator.call(**args, allocations: [{ product_id: "etf", allocation_percent: 80 }]) }.to raise_error(FinancialProducts::Error)
    expect { Investments::PortfolioSimulator.call(**args, allocations: [{ product_id: "etf", allocation_percent: 50 }, { product_id: "etf", allocation_percent: 50 }]) }.to raise_error(FinancialProducts::Error)
    expect { Investments::PortfolioSimulator.call(**args, allocations: [{ product_id: "unknown", allocation_percent: 100 }]) }.to raise_error(FinancialProducts::Error)
  end
end
