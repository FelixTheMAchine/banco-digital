class CreditRule < ApplicationRecord
  DEFAULTS = {
    "monthly_rate" => "0.019", "max_commitment_ratio" => "0.30",
    "disposable_buffer_ratio" => "0.65", "debt_assessment_months" => 24,
    "max_amount_cents" => 5_000_000, "max_term_months" => 60,
    "min_relationship_days" => 0, "min_internal_score" => 40
  }.freeze
  validates :name, presence: true, length: { maximum: 120 }
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: true
  validate :valid_configuration
  validate :immutable_config, on: :update

  def self.current_config
    rule = find_by(active: true)
    [rule ? DEFAULTS.merge(rule.config) : DEFAULTS.dup, rule&.version || 0]
  end

  def self.activate!(config:, admin:)
    raise FinancialProducts::Error, "Acesso administrativo necessário." unless admin.role == "admin" && admin.active?
    raise FinancialProducts::Error, "Configuração inválida." unless config.is_a?(Hash)

    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(740021)")
      current, = current_config
      rule = new(name: "Regras demonstrativas", version: (maximum(:version) || 0) + 1,
        config: current.merge(config.stringify_keys), active: false)
      rule.save!
      where(active: true).update_all(active: false)
      rule.update!(active: true)
      AuditLog.create!(user: admin, action: "credit.rule_activated", subject_id: rule.id)
      rule
    end
  end

  def public_json
    as_json(only: %i[id name version config active created_at])
  end

  private

  def valid_configuration
    unless config.is_a?(Hash) && (config.keys - DEFAULTS.keys).empty?
      errors.add(:config, :invalid)
      return
    end
    values = DEFAULTS.merge(config)
    FinancialProducts::Input.decimal(values["monthly_rate"], "Taxa mensal", min: "0", max: "0.10")
    FinancialProducts::Input.decimal(values["max_commitment_ratio"], "Comprometimento", min: "0.05", max: "0.50")
    FinancialProducts::Input.decimal(values["disposable_buffer_ratio"], "Margem de renda", min: "0.10", max: "0.90")
    FinancialProducts::Input.integer(values["debt_assessment_months"], "Prazo presumido de dívidas", min: 1, max: 120)
    FinancialProducts::Input.integer(values["max_amount_cents"], "Limite demonstrativo", min: 1000, max: 100_000_000)
    FinancialProducts::Input.integer(values["max_term_months"], "Prazo máximo", min: 1, max: 120)
    FinancialProducts::Input.integer(values["min_relationship_days"], "Relacionamento mínimo", min: 0, max: 3650)
    FinancialProducts::Input.integer(values["min_internal_score"], "Score mínimo", min: 0, max: 100)
  rescue FinancialProducts::Error
    errors.add(:config, :invalid)
  end

  def immutable_config
    errors.add(:config, :readonly) if will_save_change_to_config? || will_save_change_to_version?
  end
end
