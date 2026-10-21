class User < ApplicationRecord
  PASSWORD_OPTIONS = { t_cost: 2, m_cost: 16, p_cost: 1 }.freeze
  MONEY_FIELDS = %i[monthly_salary_cents other_income_cents monthly_expenses_cents existing_debts_cents].freeze
  MAX_CENTS = 9_000_000_000_000_000
  PUBLIC_FIELDS = %i[id full_name email birth_date phone address profession monthly_salary_cents
                     other_income_cents monthly_expenses_cents existing_debts_cents investor_profile status role created_at].freeze

  has_many :auth_sessions, dependent: :restrict_with_exception
  has_many :purpose_tokens, dependent: :restrict_with_exception
  has_many :audit_logs, dependent: :restrict_with_exception
  has_one :account, dependent: :restrict_with_exception
  has_many :loans, dependent: :restrict_with_exception
  has_many :investment_simulations, dependent: :restrict_with_exception
  has_many :financial_goals, dependent: :restrict_with_exception
  has_many :notifications, dependent: :restrict_with_exception
  encrypts :mfa_secret, :mfa_pending_secret
  attr_accessor :password, :password_confirmation

  before_validation :normalize_identity
  before_save :hash_password, if: -> { password.present? }
  after_save :clear_password_input
  validates :full_name, :cpf, :birth_date, :email, :phone, :profession, presence: true
  validates :full_name, length: { maximum: 150 }
  validates :profession, length: { maximum: 120 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }, uniqueness: { case_sensitive: false }
  validates :cpf, cpf: true, uniqueness: true
  validates :phone, format: { with: /\A\+[1-9][0-9]{9,14}\z/ }
  validates :role, inclusion: { in: %w[customer admin] }
  validates :status, inclusion: { in: %w[active blocked deactivated] }
  validates :investor_profile, inclusion: { in: %w[not_assessed conservative moderate aggressive] }
  validate :adult_age
  validate :valid_address
  validate :valid_monetary_inputs
  validate :valid_password

  def authenticate(candidate)
    return false unless candidate.is_a?(String) && candidate.bytesize <= 512 && password_digest.present?
    Argon2::Password.verify_password(candidate, password_digest) ? self : false
  rescue Argon2::ArgonHashFail
    false
  end

  def active?
    status == "active"
  end

  def mfa_enabled?
    mfa_enabled_at.present?
  end

  def public_json
    as_json(only: PUBLIC_FIELDS).merge(
      "cpf" => "***.***.***-#{cpf.last(2)}",
      "email_verified" => email_verified_at.present?,
      "mfa_enabled" => mfa_enabled?,
      "income_commitment_percent" => income_commitment_percent
    )
  end

  def income_commitment_percent
    income = monthly_salary_cents + other_income_cents
    return "0.0" if income.zero?
    (BigDecimal(monthly_expenses_cents.to_s) * 100 / income).round(2).to_s("F")
  end

  private

  def normalize_identity
    self.email = email.strip.downcase if email.is_a?(String)
    self.cpf = cpf.delete(". -") if cpf.is_a?(String)
    self.full_name = full_name.strip if full_name.is_a?(String)
  end

  def valid_password
    return unless new_record? || !password.nil?
    unless password.is_a?(String) && password.length.between?(12, 128) && password.bytesize <= 512
      errors.add(:password, :invalid)
      return
    end
    errors.add(:password_confirmation, :confirmation) unless password == password_confirmation
  end

  def hash_password
    self.password_digest = Argon2::Password.create(password, **PASSWORD_OPTIONS)
  end

  def clear_password_input
    self.password = nil
    self.password_confirmation = nil
  end

  def adult_age
    errors.add(:birth_date, :invalid) unless birth_date && birth_date >= Date.new(1900, 1, 1) && birth_date <= Date.current - 18.years
  end

  def valid_monetary_inputs
    MONEY_FIELDS.each do |field|
      raw = public_send("#{field}_before_type_cast")
      database_default = new_record? && !attribute_came_from_user?(field.to_s) && public_send(field) == 0
      errors.add(field, :invalid) unless database_default || (raw.is_a?(Integer) && raw.between?(0, MAX_CENTS))
    end
  end

  def valid_address
    required = %w[street number city state postal_code]
    unless address.is_a?(Hash) && required.all? { |key| address[key].is_a?(String) && address[key].strip.present? && address[key].length <= 160 }
      errors.add(:address, :invalid)
      return
    end
    errors.add(:address, :invalid) unless address["state"].match?(/\A[A-Z]{2}\z/) && address["postal_code"].match?(/\A[0-9]{8}\z/)
  end
end
