require "rails_helper"

RSpec.describe User, type: :model do
  it "stores an Argon2id digest and authenticates only the correct password" do
    user = create_user
    expect(user.password_digest).to start_with("$argon2id$")
    expect(user.password_digest).not_to include("Ficticia-Forte")
    expect(user.authenticate("Ficticia-Forte-9347!")).to be_truthy
    expect(user.authenticate("incorrect-password")).to be_falsey
  end

  it "normalizes email and rejects a case-insensitive duplicate" do
    user = create_user(email: "CLIENTE@Example.Test ")
    expect(user.reload.email).to eq("cliente@example.test")
    duplicate = User.new(user_attributes(email: "Cliente@example.test"))
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to be_present
  end

  it "validates CPF checksums and rejects repeated digits" do
    %w[12345678900 11111111111 00000000000 abc].each do |cpf|
      user = User.new(user_attributes(cpf: cpf))
      expect(user).not_to be_valid
      expect(user.errors[:cpf]).to be_present
    end
  end

  it "rejects underage and future birth dates" do
    [Date.current - 17.years, Date.current + 1.day].each do |birth_date|
      user = User.new(user_attributes(birth_date: birth_date))
      expect(user).not_to be_valid
      expect(user.errors[:birth_date]).to be_present
    end
  end

  it "accepts a customer on their eighteenth birthday" do
    expect(User.new(user_attributes(birth_date: Date.current - 18.years))).to be_valid
  end

  it "rejects negative income and expenses" do
    %i[monthly_salary_cents other_income_cents monthly_expenses_cents existing_debts_cents].each do |attribute|
      user = User.new(user_attributes(attribute => -1))
      expect(user).not_to be_valid
      expect(user.errors[attribute]).to be_present
    end
  end

  it "rejects fractional cents instead of silently truncating them" do
    user = User.new(user_attributes(monthly_salary_cents: 100.5))
    expect(user).not_to be_valid
    expect(user.errors[:monthly_salary_cents]).to be_present
  end

  it "accepts zero declared income without inventing credit" do
    expect(User.new(user_attributes(monthly_salary_cents: 0, other_income_cents: 0))).to be_valid
  end

  it "uses zero defaults for omitted optional declarations but rejects numeric strings supplied by a client" do
    user = User.new(user_attributes.except(:other_income_cents, :monthly_expenses_cents, :existing_debts_cents))
    expect(user).to be_valid
    expect(user.other_income_cents).to eq(0)
    user.other_income_cents = "0"
    expect(user).not_to be_valid
    expect(user.errors[:other_income_cents]).to be_present
  end

  it "requires matching password confirmation" do
    user = User.new(user_attributes(password_confirmation: "Different-Ficticia-9347!"))
    expect(user).not_to be_valid
  end

  it "does not expose secrets or the full CPF in its public representation" do
    user = create_user
    public_data = user.public_json.to_json
    expect(public_data).not_to include(user.password_digest, user.cpf, "password_digest", "email_verified_at")
    expect(public_data).to include(user.email)
  end
end
