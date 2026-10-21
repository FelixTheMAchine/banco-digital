require "digest"
require "json"

module Credit
  class Applications
    class << self
      def submit!(user:, amount_cents:, term_months:, idempotency_key:, monthly_debt_payment_cents: nil)
        key = valid_key!(idempotency_key)
        FinancialProducts::Input.integer(amount_cents, "Valor solicitado", min: 1000, max: 100_000_000)
        FinancialProducts::Input.integer(term_months, "Prazo", min: 1, max: 120)
        FinancialProducts::Input.integer(monthly_debt_payment_cents, "Prestação de dívidas") unless monthly_debt_payment_cents.nil?
        digest = Digest::SHA256.hexdigest(JSON.generate([amount_cents, term_months, monthly_debt_payment_cents]))
        user.with_lock do
          raise FinancialProducts::Error, "Perfil indisponível para novas solicitações." unless user.active?
          previous = Loan.find_by(user_id: user.id, idempotency_key: key)
          if previous
            raise FinancialProducts::Conflict.new("A chave de idempotência já foi usada com outros dados.", code: "idempotency_conflict") unless previous.request_digest == digest
            next previous
          end

          evaluation = Evaluator.call(user: user, amount_cents: amount_cents, term_months: term_months,
            monthly_debt_payment_cents: monthly_debt_payment_cents)
          loan = Loan.create!(user: user, amount_cents: amount_cents, term_months: term_months,
            monthly_rate: BigDecimal(evaluation[:monthly_rate_percent]) / 100,
            installment_cents: evaluation[:installment_cents], total_cents: evaluation[:total_cents],
            status: evaluation[:eligible] ? "pending_review" : "rejected", eligibility_snapshot: evaluation,
            rule_version: evaluation[:rule_version], idempotency_key: key, request_digest: digest)
          evaluation.fetch(:schedule).each { |row| loan.loan_installments.create!(row) }
          AuditLog.create!(user: user, action: "credit.application_created", subject_id: loan.id)
          loan
        end
      end

      def appeal!(loan:, user:, reason:)
        reason = FinancialProducts::Input.text(reason, "Motivo da contestação", min: 10, max: 2000)
        user.with_lock do
          loan.lock!
          raise ActiveRecord::RecordNotFound unless loan.user_id == user.id
          unless %w[rejected reviewed_rejected].include?(loan.status)
            raise FinancialProducts::Conflict.new("Somente decisões de rejeição podem ser contestadas.", code: "appeal_not_eligible")
          end
          if loan.loan_appeals.exists?(status: "pending_review")
            raise FinancialProducts::Conflict.new("Já existe contestação em revisão.", code: "appeal_pending")
          end

          appeal = loan.loan_appeals.create!(user: user, reason: reason)
          loan.update!(status: "pending_review")
          AuditLog.create!(user: user, action: "credit.appeal_created", subject_id: appeal.id)
          appeal
        end
      end

      def review!(loan:, admin:, decision:, reason:)
        raise FinancialProducts::Error, "Acesso administrativo necessário." unless admin.role == "admin" && admin.active?
        decision = FinancialProducts::Input.choice(decision, %w[approve reject], "Decisão")
        reason = FinancialProducts::Input.text(reason, "Motivo da decisão", min: 10, max: 2000)
        loan.with_lock do
          unless loan.status == "pending_review"
            raise FinancialProducts::Conflict.new("Esta solicitação não está aguardando revisão.", code: "review_not_pending")
          end
          now = Time.current
          loan.update!(status: decision == "approve" ? "approved" : "reviewed_rejected",
            reviewed_by: admin, reviewed_at: now, review_reason: reason)
          loan.loan_appeals.where(status: "pending_review").find_each do |appeal|
            appeal.update!(status: "reviewed", outcome: { decision: decision, reason: reason, reviewed_at: now.iso8601 })
          end
          AuditLog.create!(user: admin, action: "credit.application_#{decision}", subject_id: loan.id)
          loan
        end
      end

      private

      def valid_key!(value)
        unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9._:-]{8,128}\z/)
          raise FinancialProducts::Error.new("Informe Idempotency-Key com 8 a 128 caracteres seguros.", code: "idempotency_key_required")
        end
        value
      end
    end
  end
end
