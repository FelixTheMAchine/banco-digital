require "bigdecimal"
require "bigdecimal/math"

module Investments
  class Simulator
    PRECISION = 40

    def self.call(initial_amount_cents:, monthly_contribution_cents:, months:, annual_rate_percent:)
      input = FinancialProducts::Input
      initial = input.integer(initial_amount_cents, "Valor inicial", max: 100_000_000)
      monthly = input.integer(monthly_contribution_cents, "Aporte mensal", max: 100_000_000)
      term = input.integer(months, "Prazo", min: 1, max: 600)
      rate = input.decimal(annual_rate_percent, "Taxa anual fictícia", min: "-20", max: "50")
      base = project(initial, monthly, term, rate)
      scenarios = [
        ["adverso", [rate - 3, BigDecimal("-20")].max],
        ["base", rate],
        ["favorável", [rate + 3, BigDecimal("50")].min]
      ].map do |name, scenario_rate|
        { name: name, annual_rate_percent: scenario_rate.to_s("F"),
          final_cents: project(initial, monthly, term, scenario_rate).fetch(:final_cents) }
      end
      { initial_amount_cents: initial, monthly_contribution_cents: monthly, months: term,
        annual_rate_percent: rate.to_s("F"), **base, scenarios: scenarios }
    end

    def self.save!(user:, **arguments)
      result = call(**arguments)
      user.with_lock do
        raise FinancialProducts::Error, "Perfil cadastral indisponível." unless user.active?
        simulation = InvestmentSimulation.create!(user: user, **result)
        AuditLog.create!(user: user, action: "investment.simulation_created", subject_id: simulation.id)
        simulation
      end
    end

    def self.project(initial, monthly, months, annual_rate)
      monthly_rate = if annual_rate.zero?
        BigDecimal("0")
      else
        BigMath.exp(BigMath.log(1 + annual_rate / 100, PRECISION) / 12, PRECISION) - 1
      end
      balance = initial
      contributed = initial
      projection = [{ month: 0, balance_cents: balance, contributed_cents: contributed }]
      (1..months).each do |month|
        balance = (BigDecimal(balance.to_s) * (1 + monthly_rate)).round(0, BigDecimal::ROUND_HALF_UP).to_i + monthly
        contributed += monthly
        if balance > FinancialProducts::Input::MAX_CENTS
          raise FinancialProducts::Error, "A projeção excede o limite de representação segura; reduza prazo ou valores."
        end
        projection << { month: month, balance_cents: balance, contributed_cents: contributed }
      end
      { final_cents: balance, contributed_cents: contributed, earnings_cents: balance - contributed, projection: projection }
    end
    private_class_method :project
  end
end
