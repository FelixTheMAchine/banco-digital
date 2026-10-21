class CreateIdentityFoundation < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")
    create_table :users, id: :uuid do |t|
      t.string :full_name, limit: 150, null: false
      t.string :cpf, limit: 11, null: false
      t.date :birth_date, null: false
      t.string :email, limit: 254, null: false
      t.string :phone, limit: 16, null: false
      t.jsonb :address, null: false
      t.string :profession, limit: 120, null: false
      t.bigint :monthly_salary_cents, null: false, default: 0
      t.bigint :other_income_cents, null: false, default: 0
      t.bigint :monthly_expenses_cents, null: false, default: 0
      t.bigint :existing_debts_cents, null: false, default: 0
      t.string :investor_profile, null: false, default: "not_assessed"
      t.string :status, null: false, default: "active"
      t.string :role, null: false, default: "customer"
      t.string :password_digest, null: false
      t.datetime :email_verified_at
      t.timestamps
    end
    add_index :users, "lower(email)", unique: true, name: "index_users_on_normalized_email"
    add_index :users, :cpf, unique: true
    add_check_constraint :users, "cpf ~ '^[0-9]{11}$'", name: "users_cpf_format"
    add_check_constraint :users, "email = lower(trim(email))", name: "users_normalized_email"
    add_check_constraint :users, "role IN ('customer', 'admin')", name: "users_role"
    add_check_constraint :users, "status IN ('active', 'blocked', 'deactivated')", name: "users_status"
    add_check_constraint :users, "investor_profile IN ('not_assessed', 'conservative', 'moderate', 'aggressive')", name: "users_investor_profile"
    add_check_constraint :users, "password_digest LIKE '$argon2id$%'", name: "users_argon2id_password"
    add_check_constraint :users, "jsonb_typeof(address) = 'object'", name: "users_address_object"
    %w[monthly_salary_cents other_income_cents monthly_expenses_cents existing_debts_cents].each do |column|
      add_check_constraint :users, "#{column} BETWEEN 0 AND 9000000000000000", name: "users_#{column}_bounds"
    end

    create_table :auth_sessions, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :restrict }
      t.string :access_digest, limit: 64, null: false
      t.string :refresh_digest, limit: 64, null: false
      t.uuid :family_id, null: false
      t.datetime :access_expires_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :auth_sessions, :access_digest, unique: true
    add_index :auth_sessions, :refresh_digest, unique: true
    add_index :auth_sessions, :family_id
    add_index :auth_sessions, :expires_at
    add_check_constraint :auth_sessions, "access_expires_at <= expires_at", name: "sessions_valid_expiry"
    %w[access_digest refresh_digest].each do |column|
      add_check_constraint :auth_sessions, "#{column} ~ '^[0-9a-f]{64}$'", name: "sessions_#{column}_format"
    end

    create_table :purpose_tokens, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :restrict }
      t.string :purpose, null: false
      t.string :token_digest, limit: 64, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :purpose_tokens, :token_digest, unique: true
    add_index :purpose_tokens, %i[user_id purpose]
    add_index :purpose_tokens, :expires_at
    add_check_constraint :purpose_tokens, "purpose IN ('email_verification', 'password_reset')", name: "tokens_valid_purpose"
    add_check_constraint :purpose_tokens, "token_digest ~ '^[0-9a-f]{64}$'", name: "tokens_digest_format"

    create_table :audit_logs, id: :uuid do |t|
      t.references :user, type: :uuid, foreign_key: { on_delete: :restrict }
      t.string :action, limit: 100, null: false
      t.uuid :subject_id
      t.string :request_id
      t.datetime :created_at, null: false
    end
    add_index :audit_logs, :created_at
    add_index :audit_logs, %i[action created_at]
  end
end
