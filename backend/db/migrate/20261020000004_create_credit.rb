class CreateCredit < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_rules, id: :uuid do |t|
      t.string :name, null: false, default: "Regras demonstrativas"
      t.integer :version, null: false
      t.jsonb :config, null: false, default: {}
      t.boolean :active, null: false, default: false
      t.timestamps
    end
    add_index :credit_rules, :version, unique: true
    add_index :credit_rules, :active, unique: true, where: "active = true", name: "one_active_credit_rule"
    add_check_constraint :credit_rules, "version > 0 AND jsonb_typeof(config) = 'object'", name: "credit_rules_valid_config"

    create_table :loans, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.bigint :amount_cents, null: false
      t.integer :term_months, null: false
      t.decimal :monthly_rate, precision: 12, scale: 8, null: false
      t.bigint :installment_cents, null: false
      t.bigint :total_cents, null: false
      t.string :status, null: false
      t.jsonb :eligibility_snapshot, null: false, default: {}
      t.integer :rule_version, null: false, default: 0
      t.string :idempotency_key, limit: 128, null: false
      t.string :request_digest, limit: 64, null: false
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :restrict }
      t.datetime :reviewed_at
      t.string :review_reason, limit: 2000
      t.timestamps
    end
    add_index :loans, %i[user_id idempotency_key], unique: true
    add_index :loans, %i[status created_at]
    add_check_constraint :loans, "amount_cents BETWEEN 1 AND 9000000000000000 AND installment_cents > 0 AND total_cents >= amount_cents", name: "loans_positive_money"
    add_check_constraint :loans, "term_months BETWEEN 1 AND 120 AND monthly_rate BETWEEN 0 AND 0.10", name: "loans_valid_terms"
    add_check_constraint :loans, "status IN ('pending_review', 'rejected', 'approved', 'reviewed_rejected')", name: "loans_valid_status"

    create_table :loan_installments, id: :uuid do |t|
      t.references :loan, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.integer :number, null: false
      t.date :due_date, null: false
      t.bigint :principal_cents, null: false
      t.bigint :interest_cents, null: false
      t.bigint :payment_cents, null: false
      t.bigint :balance_cents, null: false
      t.string :status, null: false, default: "simulated"
      t.timestamps
    end
    add_index :loan_installments, %i[loan_id number], unique: true
    add_check_constraint :loan_installments, "number > 0 AND principal_cents >= 0 AND interest_cents >= 0 AND payment_cents = principal_cents + interest_cents AND balance_cents >= 0", name: "installments_valid_amounts"
    add_check_constraint :loan_installments, "status IN ('simulated', 'paid', 'overdue')", name: "installments_valid_status"

    create_table :loan_appeals, id: :uuid do |t|
      t.references :loan, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.string :reason, limit: 2000, null: false
      t.string :status, null: false, default: "pending_review"
      t.jsonb :outcome, null: false, default: {}
      t.timestamps
    end
    add_index :loan_appeals, :loan_id, unique: true, where: "status = 'pending_review'", name: "one_pending_appeal_per_loan"
    add_check_constraint :loan_appeals, "status IN ('pending_review', 'reviewed')", name: "appeals_valid_status"
  end
end
