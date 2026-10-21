module Banking
  class Reconciliation
    def self.call(account: nil)
      mismatches = []
      checked = 0
      scope = account ? Account.where(id: account.id) : Account.all
      scope.find_each do |candidate|
        candidate.user.with_lock(requires_new: true) do
          candidate.lock!
          actual = candidate.ledger_account.balance_cents
          cached = candidate.available_cents + candidate.blocked_cents
          checked += 1
          next if actual == cached

          mismatches << { account_id: candidate.id, ledger_cents: actual, cached_cents: cached }
          candidate.update!(status: "blocked") unless candidate.status == "closed"
          SecurityEvent.create!(user_id: candidate.user_id, account: candidate, kind: "reconciliation_mismatch", severity: "high",
            reasons: ["ledger_and_cached_balance_disagree"])
          AuditLog.create!(action: "banking.reconciliation_mismatch", subject_id: candidate.id)
        end
      end
      { checked_accounts: checked, mismatches: mismatches, reconciled: mismatches.empty? }
    end
  end
end
