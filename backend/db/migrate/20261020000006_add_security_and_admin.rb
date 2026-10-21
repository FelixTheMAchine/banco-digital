class AddSecurityAndAdmin < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :mfa_secret, :text
    add_column :users, :mfa_pending_secret, :text
    add_column :users, :mfa_enabled_at, :datetime
    add_column :users, :mfa_pending_expires_at, :datetime
    add_column :users, :mfa_last_otp_at, :bigint
    add_column :users, :mfa_recovery_digests, :jsonb, null: false, default: []
    add_column :auth_sessions, :mfa_verified_at, :datetime
    add_check_constraint :users, "jsonb_typeof(mfa_recovery_digests) = 'array' AND jsonb_array_length(mfa_recovery_digests) <= 8", name: "users_mfa_recovery_array"
    add_check_constraint :users, "mfa_enabled_at IS NULL OR mfa_secret IS NOT NULL", name: "users_mfa_enabled_secret"
    add_check_constraint :users, "mfa_last_otp_at IS NULL OR mfa_last_otp_at >= 0", name: "users_mfa_positive_step"
    add_check_constraint :users, "(mfa_pending_secret IS NULL) = (mfa_pending_expires_at IS NULL)", name: "users_mfa_pending_expiry"
    create_table :financial_rules, id: :uuid do |t|
      t.string :key, null: false
      t.bigint :value, null: false
      t.bigint :version, null: false, default: 1
      t.references :updated_by, type: :uuid, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :financial_rules, :key, unique: true
    add_check_constraint :financial_rules, "value BETWEEN 1 AND 9000000000000000", name: "financial_rule_positive_value"
    add_check_constraint :financial_rules, "version > 0", name: "financial_rule_positive_version"
    add_check_constraint :financial_rules, "key IN ('banking.daily_limit_cents', 'fraud.high_value_cents', 'banking.max_transaction_cents', 'fraud.attempts_per_minute', 'fraud.cooldown_seconds')", name: "financial_rule_known_key"
  end
end
