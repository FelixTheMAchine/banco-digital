require "bigdecimal"

module Credit
  class Evaluator
    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(user:, amount_cents:, term_months:, monthly_debt_payment_cents: nil)
      @user = user
      @amount = FinancialProducts::Input.integer(amount_cents, "Valor solicitado", min: 1000, max: 100_000_000)
      @term = FinancialProducts::Input.integer(term_months, "Prazo", min: 1, max: 120)
      @monthly_debt = monthly_debt_payment_cents
      FinancialProducts::Input.integer(@monthly_debt, "Prestação de dívidas") unless @monthly_debt.nil?
      @config, @version = CreditRule.current_config
    end

    def call
      rate = BigDecimal(@config.fetch("monthly_rate"))
      result = Price.schedule(amount_cents: @amount, monthly_rate: rate, term_months: @term)
      income = @user.monthly_salary_cents + @user.other_income_cents
      if income > FinancialProducts::Input::MAX_CENTS
        raise FinancialProducts::Error, "A renda total excede o limite de representação da simulação."
      end
      debt_payment = @monthly_debt || (@user.existing_debts_cents.to_d / @config.fetch("debt_assessment_months")).ceil.to_i
      available = [income - @user.monthly_expenses_cents - debt_payment, 0].max
      capacity_by_income = [(income.to_d * BigDecimal(@config.fetch("max_commitment_ratio"))).floor.to_i - debt_payment, 0].max
      capacity_by_surplus = (available.to_d * BigDecimal(@config.fetch("disposable_buffer_ratio"))).floor.to_i
      monthly_capacity = [capacity_by_income, capacity_by_surplus].min
      estimated_limit = [Price.present_value(installment_cents: monthly_capacity, monthly_rate: rate, term_months: @term), @config.fetch("max_amount_cents")].min
      relationship_days = [(Date.current - @user.created_at.to_date).to_i, 0].max
      account = Account.find_by(user_id: @user.id)
      average_balance = account ? Banking::BalanceHistory.average_cents(account: account, days: 90) : 0
      history = LoanInstallment.joins(:loan).where(loans: { user_id: @user.id })
      paid_count = history.where(status: "paid").count
      overdue_count = history.where(status: "overdue").count

      factors = [
        { factor: "base", points: 20, explanation: "Base interna demonstrativa, sem consulta a bureaus." },
        { factor: "renda_disponivel", points: available.positive? ? 25 : 0, explanation: "Renda declarada após despesas e prestação de dívidas estimada." },
        { factor: "comprometimento_atual", points: income.positive? && debt_payment * 5 <= income ? 20 : 0, explanation: "Obrigações de dívida limitadas a 20% da renda declarada." },
        { factor: "relacionamento", points: [relationship_days / 30, 15].min, explanation: "Um ponto por mês completo de relacionamento, até 15." },
        { factor: "saldo_medio", points: income.positive? ? [[average_balance * 10 / income, 10].min, 0].max : 0, explanation: "Saldo contábil médio observado, até dez pontos; não supõe histórico ausente." },
        { factor: "historico_interno", points: [[paid_count, 10].min - overdue_count * 10, -30].max, explanation: "Somente parcelas internas registradas: um ponto por pagamento, menos dez por atraso." }
      ]
      score = [[factors.sum { |factor| factor[:points] }, 0].max, 100].min
      failures = []
      failures << "A renda declarada não gera disponibilidade após as despesas e dívidas estimadas." unless available.positive?
      failures << "A parcela excede a capacidade mensal estimada de R$ #{brl(monthly_capacity)}." if result[:installment_cents] > monthly_capacity
      failures << "O valor excede o limite estimado para este prazo." if @amount > estimated_limit
      failures << "O prazo excede o máximo configurado de #{@config.fetch('max_term_months')} meses." if @term > @config.fetch("max_term_months")
      failures << "O relacionamento ainda não atingiu o mínimo configurado." if relationship_days < @config.fetch("min_relationship_days")
      failures << "O score interno demonstrativo ficou abaixo do mínimo configurado." if score < @config.fetch("min_internal_score")
      failures << "O perfil cadastral está desativado ou bloqueado." unless @user.active?
      eligible = failures.empty?
      annual_percent = ((1 + rate)**12 - 1) * 100
      commitment = income.positive? ? ((debt_payment + result[:installment_cents]).to_d * 100 / income).round(2).to_s("F") : nil
      assumptions = [
        "Simulação com dinheiro fictício; não é oferta nem contratação de crédito.",
        "Renda e despesas são autodeclaradas. Não há consulta ao Serasa, SPC ou Banco Central.",
        "Score interno demonstrativo e explicável; não representa pontuação oficial de crédito.",
        "A capacidade mensal é o menor valor entre a fração de renda configurada menos dívidas e a fração do excedente após despesas.",
        "Taxas fictícias, períodos mensais uniformes, juros compostos pelo Sistema Price e arredondamento em centavos; a última parcela ajusta o principal remanescente.",
        "CET anual estimado considera tarifas, seguros e tributos iguais a zero; equivale à taxa efetiva anual antes de pequenos efeitos de arredondamento e não constitui CET regulatório.",
        "Saldo médio utiliza o saldo contábil diário observado desde a abertura, limitado a 90 dias, incluindo saldo bloqueado. Dias anteriores à abertura não são inventados.",
        "#{paid_count} parcela(s) paga(s) e #{overdue_count} em atraso no histórico interno; simulações não são pagamentos efetivos."
      ]
      assumptions << if @monthly_debt.nil?
        "Dívidas cadastradas são um estoque, não despesa mensal: a prestação foi presumida em #{@config.fetch('debt_assessment_months')} meses (R$ #{brl(debt_payment)}/mês). Informe a prestação real para comparar cenários."
      else
        "Prestação mensal de dívidas declarada especificamente para este cenário."
      end
      assumptions << "Sem renda positiva, o comprometimento percentual é indefinido e retorna null; a solicitação é inelegível." unless income.positive?
      result.merge(eligible: eligible, amount_cents: @amount, term_months: @term,
        monthly_rate_percent: (rate * 100).to_s("F"), annual_effective_rate_percent: annual_percent.round(4).to_s("F"),
        estimated_cet_annual_percent: annual_percent.round(4).to_s("F"), available_income_cents: available,
        monthly_capacity_cents: monthly_capacity, estimated_limit_cents: estimated_limit,
        commitment_percent: commitment, internal_score: score, score_factors: factors,
        average_balance_cents: average_balance, relationship_days: relationship_days,
        rule_version: @version, reasons: eligible ? ["Parcela compatível com a renda disponível e com os limites configurados; aprovação preliminar sujeita à revisão simulada."] : failures,
        assumptions: assumptions, alternative_terms: alternative_terms(rate, monthly_capacity))
    end

    private

    def alternative_terms(rate, capacity)
      [6, 12, 24, 36, 48, 60].select { |term| term <= @config.fetch("max_term_months") }.map do |term|
        price = Price.schedule(amount_cents: @amount, monthly_rate: rate, term_months: term)
        { term_months: term, installment_cents: price[:installment_cents], total_cents: price[:total_cents],
          fits_monthly_capacity: price[:installment_cents] <= capacity }
      end
    end

    def brl(cents)
      (BigDecimal(cents.to_s) / 100).round(2).to_s("F").tr(".", ",")
    end
  end
end
