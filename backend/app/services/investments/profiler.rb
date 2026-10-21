module Investments
  class Profiler
    ANSWER_KEYS = %w[risk_tolerance knowledge horizon_months liquidity_need emergency_reserve_cents goal monthly_contribution_cents].freeze
    ALLOCATIONS = {
      "conservative" => { "tesouro-selic" => 50, "cdb" => 25, "lci-lca" => 15, "fixed-income-fund" => 10 },
      "moderate" => { "tesouro-selic" => 25, "tesouro-ipca" => 20, "cdb" => 20, "lci-lca" => 15, "fixed-income-fund" => 10, "real-estate-fund" => 5, "etf" => 5 },
      "aggressive" => { "tesouro-selic" => 15, "tesouro-ipca" => 15, "cdb" => 10, "lci-lca" => 5, "fixed-income-fund" => 5, "real-estate-fund" => 15, "etf" => 20, "stocks" => 15 }
    }.freeze

    def self.call(user:, answers:)
      new(user: user, answers: answers).call
    end

    def self.save!(user:, answers:)
      user.with_lock do
        raise FinancialProducts::Error, "Perfil cadastral indisponível." unless user.active?

        result = call(user: user, answers: answers)
        profile = InvestmentProfile.find_or_initialize_by(user_id: user.id)
        profile.assign_attributes(result)
        profile.save!
        user.update!(investor_profile: profile.profile)
        AuditLog.create!(user: user, action: "investment.profile_updated", subject_id: profile.id)
        profile
      end
    end

    def initialize(user:, answers:)
      raise FinancialProducts::Error, "Questionário inválido." unless answers.is_a?(Hash)
      @user = user
      @answers = answers.stringify_keys.slice(*ANSWER_KEYS)
      validate_answers!
    end

    def call
      income = @user.monthly_salary_cents + @user.other_income_cents
      expenses = @user.monthly_expenses_cents
      debt_payment = (@user.existing_debts_cents.to_d / 24).ceil.to_i
      disposable = [income - expenses - debt_payment, 0].max
      reserve_months = @user.monthly_salary_cents.zero? ? 12 : 6
      target = expenses * reserve_months
      if income > FinancialProducts::Input::MAX_CENTS || target > FinancialProducts::Input::MAX_CENTS
        raise FinancialProducts::Error, "A renda ou reserva-alvo excede o limite de representação da simulação."
      end
      reserve_gap = [target - @answers.fetch("emergency_reserve_cents"), 0].max
      account = Account.find_by(user_id: @user.id)
      balance = account&.available_cents || 0
      investable = [balance - reserve_gap, 0].max
      score = { "low" => 10, "medium" => 35, "high" => 55 }.fetch(@answers.fetch("risk_tolerance"))
      score += { "beginner" => 5, "intermediate" => 15, "advanced" => 25 }.fetch(@answers.fetch("knowledge"))
      score += @answers.fetch("horizon_months") >= 36 ? 10 : (@answers.fetch("horizon_months") < 12 ? -30 : 0)
      score -= { "high" => 25, "medium" => 10, "low" => 0 }.fetch(@answers.fetch("liquidity_need"))
      score -= 25 if reserve_gap.positive?
      score -= 20 if @user.existing_debts_cents > income * 6
      score = [[score, 0].max, 100].min
      profile = score >= 65 ? "aggressive" : (score >= 35 ? "moderate" : "conservative")
      warnings = ["Questionário autodeclarado, sem certificação de adequação. Refaça após mudanças de renda, dívidas, objetivos ou prazo."]
      warnings << "A reserva estimada corresponde a #{reserve_months} meses de despesas; use despesas essenciais reais para aperfeiçoar o planejamento."
      warnings << "Dívidas cadastradas foram divididas em 24 meses apenas para estimar a prestação; não representam consulta externa."
      if reserve_gap.positive?
        profile = "conservative"
        warnings << "Priorize completar a reserva de emergência antes de assumir risco de mercado."
      end
      if disposable.zero?
        profile = "conservative"
        investable = 0
        warnings << "Não há renda mensal disponível estimada: reorganize despesas e dívidas antes de novos aportes."
      end
      if @answers.fetch("horizon_months") < 12 || @answers.fetch("liquidity_need") == "high"
        profile = "conservative"
        warnings << "Prazo curto ou alta necessidade de liquidez restringe a exposição a ativos voláteis."
      elsif @answers.fetch("knowledge") == "beginner" && profile == "aggressive"
        profile = "moderate"
        warnings << "Conhecimento inicial limita a exposição educativa a ativos mais complexos."
      end
      if @answers.fetch("monthly_contribution_cents") > disposable
        warnings << "O aporte declarado excede a renda disponível estimada e deve ser reduzido; esta tela não movimenta recursos."
      end
      if @user.existing_debts_cents.positive?
        warnings << "Compare o custo das dívidas com cenários conservadores antes de investir; a taxa das suas dívidas não é conhecida pelo simulador."
      end
      allocation = if reserve_gap.positive? || disposable.zero? || @answers.fetch("horizon_months") < 12 || @answers.fetch("liquidity_need") == "high"
        { "tesouro-selic" => 100 }
      else
        ALLOCATIONS.fetch(profile)
      end
      recommendations = allocation.map do |product_id, percentage|
        product = Products::LIST.find { |item| item[:id] == product_id }
        { product_id: product_id, asset_class: product[:asset_class], allocation_percent: percentage,
          risk: product[:risk], liquidity: product[:liquidity],
          reason: reason_for(product_id, reserve_gap, profile) }
      end
      { profile: profile, score: score, answers: @answers, recommendations: recommendations,
        emergency_target_cents: target, available_to_invest_cents: investable, warnings: warnings }
    end

    private

    def validate_answers!
      input = FinancialProducts::Input
      input.choice(@answers["risk_tolerance"], %w[low medium high], "Tolerância ao risco")
      input.choice(@answers["knowledge"], %w[beginner intermediate advanced], "Conhecimento financeiro")
      input.choice(@answers["liquidity_need"], %w[low medium high], "Necessidade de liquidez")
      input.integer(@answers["horizon_months"], "Prazo de investimento", min: 1, max: 600)
      input.integer(@answers["emergency_reserve_cents"], "Reserva de emergência")
      input.integer(@answers["monthly_contribution_cents"], "Aporte mensal", max: 100_000_000)
      @answers["goal"] = input.text(@answers["goal"], "Objetivo", min: 3, max: 200)
    end

    def reason_for(product_id, reserve_gap, profile)
      if product_id == "tesouro-selic"
        reserve_gap.positive? ? "Foco educativo na construção da reserva e em liquidez; o valor sugerido não é uma aplicação executável." : "Parcela de liquidez para objetivos e imprevistos, conforme o perfil #{profile}."
      elsif %w[tesouro-ipca cdb lci-lca fixed-income-fund].include?(product_id)
        "Diversificação educativa em renda fixa, compatível com o horizonte informado; confira risco de crédito, carência e marcação a mercado."
      else
        "Exposição limitada a renda variável para horizonte longo e tolerância declarada; pode perder valor e exige diversificação."
      end
    end
  end
end
