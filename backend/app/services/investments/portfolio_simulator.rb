module Investments
  class PortfolioSimulator
    def self.call(initial_amount_cents:, monthly_contribution_cents:, months:, allocations:)
      input = FinancialProducts::Input
      initial = input.integer(initial_amount_cents, "Valor inicial", max: 100_000_000)
      monthly = input.integer(monthly_contribution_cents, "Aporte mensal", max: 100_000_000)
      term = input.integer(months, "Prazo", min: 1, max: 600)
      unless allocations.is_a?(Array) && allocations.length.between?(1, 8) && allocations.all? { |item| item.is_a?(Hash) }
        raise FinancialProducts::Error, "Informe de uma a oito classes de ativos na carteira."
      end
      items = allocations.map(&:stringify_keys)
      product_ids = items.map { |item| item["product_id"] }
      raise FinancialProducts::Error, "Não repita classes na carteira." unless product_ids.uniq.length == product_ids.length

      percentages = items.map { |item| input.integer(item["allocation_percent"], "Percentual da carteira", min: 1, max: 100) }
      raise FinancialProducts::Error, "A soma dos percentuais deve ser 100%." unless percentages.sum == 100

      initial_parts = split_cents(initial, percentages)
      monthly_parts = split_cents(monthly, percentages)
      components = items.each_with_index.map do |item, index|
        product = Products::LIST.find { |candidate| candidate[:id] == item["product_id"] }
        raise FinancialProducts::Error, "Classe de ativo desconhecida." unless product

        result = Simulator.call(initial_amount_cents: initial_parts[index], monthly_contribution_cents: monthly_parts[index],
          months: term, annual_rate_percent: product[:annual_rate_percent])
        { product: product, percentage: percentages[index], initial_cents: initial_parts[index],
          monthly_cents: monthly_parts[index], simulation: result }
      end
      projection = (0..term).map do |month|
        balance = components.sum { |component| component[:simulation][:projection][month][:balance_cents] }
        raise FinancialProducts::Error, "A projeção da carteira excede o limite de representação segura." if balance > FinancialProducts::Input::MAX_CENTS

        { month: month, balance_cents: balance, contributed_cents: initial + monthly * month }
      end
      final_cents = projection.last.fetch(:balance_cents)
      contributed = initial + monthly * term
      weighted_rate = components.sum(BigDecimal("0")) { |component| BigDecimal(component[:product][:annual_rate_percent]) * component[:percentage] / 100 }
      portfolio = {
        allocations: components.map { |component|
          { product_id: component[:product][:id], asset_class: component[:product][:asset_class],
            allocation_percent: component[:percentage], annual_rate_percent: component[:product][:annual_rate_percent],
            initial_cents: component[:initial_cents], monthly_contribution_cents: component[:monthly_cents],
            final_cents: component[:simulation][:final_cents], risk: component[:product][:risk] }
        },
        assumptions: [
          "Taxas fictícias constantes por classe; não são previsões de mercado.",
          "Aportes no fim do mês com percentuais fixos e sem rebalanceamento do patrimônio acumulado.",
          "Centavos indivisíveis são distribuídos por maiores restos para preservar integralmente os aportes.",
          "A taxa anual exibida é uma média inicial para comparação; os saldos são calculados separadamente por ativo, sem usar essa média como rendimento efetivo da carteira.",
          "Cenários usam taxas fictícias de cada ativo menos três pontos percentuais, base e mais três pontos; sem probabilidades ou garantia."
        ]
      }
      scenarios = ["adverso", "base", "favorável"].each_with_index.map do |name, index|
        total = components.sum { |component| component[:simulation][:scenarios][index][:final_cents] }
        raise FinancialProducts::Error, "Um cenário da carteira excede o limite seguro." if total > FinancialProducts::Input::MAX_CENTS
        weighted_scenario_rate = components.sum(BigDecimal("0")) do |component|
          BigDecimal(component[:simulation][:scenarios][index][:annual_rate_percent]) * component[:percentage] / 100
        end
        { name: name, annual_rate_percent: weighted_scenario_rate.round(4).to_s("F"), final_cents: total }
      end
      { initial_amount_cents: initial, monthly_contribution_cents: monthly, months: term,
        annual_rate_percent: weighted_rate.round(4).to_s("F"), final_cents: final_cents,
        contributed_cents: contributed, earnings_cents: final_cents - contributed,
        projection: projection, scenarios: scenarios, portfolio: portfolio }
    end

    def self.save!(user:, **arguments)
      result = call(**arguments)
      user.with_lock do
        raise FinancialProducts::Error, "Perfil cadastral indisponível." unless user.active?
        simulation = InvestmentSimulation.create!(user: user, **result)
        AuditLog.create!(user: user, action: "investment.portfolio_simulated", subject_id: simulation.id)
        simulation
      end
    end

    def self.split_cents(total, percentages)
      parts = percentages.map { |percentage| total * percentage / 100 }
      remaining = total - parts.sum
      order = percentages.each_index.sort_by { |index| [-(total * percentages[index] % 100), index] }
      remaining.times { |index| parts[order[index]] += 1 }
      parts
    end
    private_class_method :split_cents
  end
end
