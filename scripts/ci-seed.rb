# Executar por rails runner, apenas em banco de teste isolado. Não é endpoint.
abort "Fixtures E2E exigem RAILS_ENV=test" unless Rails.env.test?
abort "Banco E2E deve terminar em _test" unless ActiveRecord::Base.connection_db_config.database.end_with?("_test")

password = ENV.fetch("E2E_PASSWORD")
email = ENV.fetch("E2E_EMAIL", "marina@example.test")
recipient_email = ENV.fetch("E2E_RECIPIENT_EMAIL", "lucas@example.test")
fixture_path = Pathname.new(ENV.fetch("E2E_ADMIN_FIXTURE", Rails.root.join("tmp/ci-admin-fixture.json").to_s)).expand_path
abort "Fixture privada deve permanecer em backend/tmp" unless fixture_path.to_s.start_with?(Rails.root.join("tmp").to_s + File::SEPARATOR)
FileUtils.mkdir_p(fixture_path.dirname)

make_user = lambda do |cpf:, name:, user_email:, suffix:|
  user = User.find_or_initialize_by(cpf: cpf)
  user.assign_attributes(
    full_name: name, email: user_email, birth_date: Date.new(1990, 1, 1), phone: "+55119999900#{suffix}",
    address: { street: "Rua de Teste", number: "100", city: "São Paulo", state: "SP", postal_code: "01001000" },
    profession: "Cliente fictício E2E", monthly_salary_cents: 600_000,
    other_income_cents: 0, monthly_expenses_cents: 200_000, existing_debts_cents: 0,
    password: password, password_confirmation: password, email_verified_at: Time.current, status: "active"
  )
  user.save!
  user
end

customer = make_user.call(cpf: "52998224725", name: "Marina Exemplo", user_email: email, suffix: "00")
recipient = make_user.call(cpf: "16899535009", name: "Lucas Exemplo", user_email: recipient_email, suffix: "01")
[customer, recipient].each do |user|
  Banking::Opening.open!(user: user)
  Banking::Operations.deposit!(user: user, amount_cents: 100_000,
    idempotency_key: "ci-opening-funds-001", description: "Depósito fictício para fluxo E2E")
end

admin = make_user.call(cpf: "11144477735", name: "Admin Exemplo", user_email: "admin-e2e@example.test", suffix: "02")
secret = ROTP::Base32.random_base32
admin.update!(role: "admin", mfa_secret: secret, mfa_enabled_at: Time.current,
  mfa_last_otp_at: nil, mfa_recovery_digests: [])
admin.auth_sessions.where(revoked_at: nil).update_all(revoked_at: Time.current)
AuditLog.create!(user: admin, action: "ci.fixture_created", subject_id: admin.id)
File.open(fixture_path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
  file.write(JSON.generate(email: admin.email, password: password, secret: secret))
end
File.chmod(0o600, fixture_path)
puts "Fixtures fictícias de cliente, destinatário e administrador MFA preparadas."
