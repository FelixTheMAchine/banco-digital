class FinancialRule < ApplicationRecord
  DEFAULTS = {
    "banking.daily_limit_cents" => 5_000_000,
    "fraud.high_value_cents" => 2_500_000,
    "banking.max_transaction_cents" => 10_000_000,
    "fraud.attempts_per_minute" => 5,
    "fraud.cooldown_seconds" => 300
  }.freeze
  VALID_RANGES = {
    "banking.daily_limit_cents" => 1..1_000_000_000_000,
    "fraud.high_value_cents" => 1..1_000_000_000_000,
    "banking.max_transaction_cents" => 1..1_000_000_000_000,
    "fraud.attempts_per_minute" => 1..100,
    "fraud.cooldown_seconds" => 30..86_400
  }.freeze
  belongs_to :updated_by, class_name: "User", optional: true
  validates :key, inclusion: { in: DEFAULTS.keys }, uniqueness: true
  validates :value, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 9_000_000_000_000_000 }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validate do
    raw = value_before_type_cast
    errors.add(:value, :invalid) unless raw.is_a?(Integer) && VALID_RANGES[key]&.cover?(raw)
  end

  def self.fetch_integer(key, default = nil)
    key = key.to_s
    raise ArgumentError, "Regra financeira desconhecida" unless DEFAULTS.key?(key)
    find_by(key: key)&.value || default || DEFAULTS.fetch(key)
  end

  def public_json
    as_json(only: %i[id key value version updated_at])
  end
end
