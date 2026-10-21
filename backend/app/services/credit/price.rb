require "bigdecimal"

module Credit
  module Price
    module_function

    def schedule(amount_cents:, monthly_rate:, term_months:, base_date: Date.current)
      FinancialProducts::Input.integer(amount_cents, "Valor solicitado", min: 1, max: 100_000_000)
      FinancialProducts::Input.integer(term_months, "Prazo", min: 1, max: 120)
      unless monthly_rate.is_a?(BigDecimal) && monthly_rate.between?(BigDecimal("0"), BigDecimal("0.10"))
        raise FinancialProducts::Error, "Taxa mensal inválida."
      end

      principal = BigDecimal(amount_cents.to_s)
      payment = if monthly_rate.zero?
        principal / term_months
      else
        growth = (1 + monthly_rate)**term_months
        principal * monthly_rate * growth / (growth - 1)
      end
      nominal = [payment.round(0, BigDecimal::ROUND_HALF_UP).to_i, 1].max
      balance = amount_cents
      rows = (1..term_months).map do |number|
        interest = (BigDecimal(balance.to_s) * monthly_rate).round(0, BigDecimal::ROUND_HALF_UP).to_i
        amortization = if number == term_months
          balance
        else
          [[nominal - interest, 0].max, balance].min
        end
        balance -= amortization
        { number: number, due_date: (base_date >> number).iso8601,
          principal_cents: amortization, interest_cents: interest,
          payment_cents: amortization + interest, balance_cents: balance }
      end
      { installment_cents: nominal, total_cents: rows.sum { |row| row[:payment_cents] }, schedule: rows }
    end

    def present_value(installment_cents:, monthly_rate:, term_months:)
      return installment_cents * term_months if monthly_rate.zero?

      growth = (1 + monthly_rate)**term_months
      (BigDecimal(installment_cents.to_s) * (growth - 1) / (monthly_rate * growth)).floor.to_i
    end
  end
end
