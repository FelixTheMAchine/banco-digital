# Carga opt-in, exclusivamente fictícia. Toda movimentação passa pelo livro-razão.
LedgerAccount.clearing!
if ENV["RUN_DEMO_SEEDS"] == "1"
  abort "Seeds de demonstração são proibidas em produção" if Rails.env.production?
  password = ENV.fetch("DEMO_PASSWORD")
  user = User.find_or_initialize_by(cpf: "52998224725")
  if user.new_record?
    user.assign_attributes(
      full_name: "Marina Exemplo", email: "marina@example.test", birth_date: Date.new(1995, 5, 10),
      phone: "+5511999990000", profession: "Desenvolvedora", monthly_salary_cents: 600_000,
      monthly_expenses_cents: 250_000, other_income_cents: 0, existing_debts_cents: 0,
      address: { street: "Rua de Teste", number: "100", city: "São Paulo", state: "SP", postal_code: "01001000" },
      password: password, password_confirmation: password, email_verified_at: Time.current
    )
    user.save!
    AuditLog.create!(user: user, action: "demo.user_created", subject_id: user.id)
  end
  recipient = User.find_or_initialize_by(cpf: "16899535009")
  if recipient.new_record?
    recipient.assign_attributes(
      full_name: "Lucas Exemplo", email: "lucas@example.test", birth_date: Date.new(1992, 3, 15),
      phone: "+5511999990001", profession: "Designer", monthly_salary_cents: 450_000,
      monthly_expenses_cents: 200_000, other_income_cents: 0, existing_debts_cents: 0,
      address: { street: "Rua de Teste", number: "200", city: "São Paulo", state: "SP", postal_code: "01001000" },
      password: password, password_confirmation: password, email_verified_at: Time.current
    )
    recipient.save!
    AuditLog.create!(user: recipient, action: "demo.user_created", subject_id: recipient.id)
  end
  [user, recipient].each { |customer| Banking::Opening.open!(user: customer) }
  Banking::Operations.deposit!(user: user, amount_cents: 600_000, idempotency_key: "demo-income-001", description: "Renda fictícia de demonstração")
  Banking::Operations.withdraw!(user: user, amount_cents: 18_490, idempotency_key: "demo-expense-001", description: "Compras simuladas")
  Banking::Operations.transfer!(user: user, destination_account_number: recipient.account.number,
    amount_cents: 25_000, idempotency_key: "demo-transfer-001", description: "Transferência fictícia de demonstração")
end
