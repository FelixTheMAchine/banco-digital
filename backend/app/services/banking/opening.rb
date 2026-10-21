require "securerandom"

module Banking
  class Opening
    def self.open!(user:, request_id: nil)
      user.with_lock(requires_new: true) do
        raise Error.new("account_unavailable", "Cadastro indisponível para abertura de conta.") unless user.active? && user.email_verified_at.present?

        existing = Account.find_by(user_id: user.id)
        next existing if existing

        number = loop do
          candidate = "#{SecureRandom.random_number(1_000_000_000).to_s.rjust(9, '0')}-#{SecureRandom.random_number(10)}"
          break candidate unless Account.exists?(number: candidate)
        end
        account = Account.create!(user: user, number: number, daily_limit_cents: Inputs.rule("banking.daily_limit_cents", 5_000_000))
        LedgerAccount.create!(account: account, code: "customer:#{account.id}", kind: "liability")
        AuditLog.create!(user: user, action: "banking.account_opened", subject_id: account.id, request_id: request_id)
        account
      end
    end
  end
end
