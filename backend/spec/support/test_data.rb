module TestData
  # Synthetic checksums for local test data; no external identity lookup occurs.
  def synthetic_cpf
    @cpf_sequence = (@cpf_sequence || 123_456_700) + 1
    digits = @cpf_sequence.to_s.rjust(9, "0").chars.map(&:to_i)
    [10, 11].each do |weight|
      remainder = digits.each_with_index.sum { |digit, index| digit * (weight - index) } % 11
      digits << (remainder < 2 ? 0 : 11 - remainder)
    end
    digits.join
  end

  def user_attributes(overrides = {})
    cpf = synthetic_cpf
    {
      full_name: "Cliente de Teste",
      cpf: cpf,
      birth_date: Date.new(1990, 5, 12),
      email: "cliente-#{SecureRandom.uuid}@example.test",
      phone: "+5511999990000",
      address: { street: "Rua de Teste", number: "10", city: "São Paulo", state: "SP", postal_code: "01001000" },
      profession: "Desenvolvedor",
      monthly_salary_cents: 600_000,
      other_income_cents: 40_000,
      monthly_expenses_cents: 200_000,
      existing_debts_cents: 30_000,
      password: "Ficticia-Forte-9347!",
      password_confirmation: "Ficticia-Forte-9347!"
    }.merge(overrides)
  end

  def create_user(overrides = {})
    User.create!(user_attributes({ email_verified_at: Time.current }.merge(overrides)))
  end

  def login_as(user, password: "Ficticia-Forte-9347!")
    post "/api/v1/auth/login", params: { email: user.email, password: password }, as: :json
    raise "Login helper failed: #{response.status}" unless response.status == 200
    JSON.parse(response.body)
  end

  def bearer_headers(tokens)
    { "Authorization" => "Bearer #{tokens.fetch('access_token')}" }
  end

  def parsed_body
    JSON.parse(response.body)
  end
end
