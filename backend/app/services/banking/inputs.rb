require "digest"
require "json"

module Banking
  module Inputs
    module_function

    def amount!(value, enforce_current_limit: true)
      maximum = enforce_current_limit ? rule("banking.max_transaction_cents", 10_000_000) : User::MAX_CENTS
      unless value.is_a?(Integer) && value.positive? && value <= [maximum, User::MAX_CENTS].min
        raise Error.new("invalid_amount", "Informe um valor positivo em centavos inteiros, dentro do limite da operação.")
      end
      value
    end

    def key!(value)
      unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_.:-]{8,128}\z/)
        raise Error.new("invalid_idempotency_key", "Envie uma chave Idempotency-Key única com 8 a 128 caracteres.", status: :bad_request)
      end
      value
    end

    def description!(value)
      value = "" if value.nil?
      unless value.is_a?(String) && value.length <= 160 && !value.match?(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/)
        raise Error.new("invalid_description", "A descrição deve ter até 160 caracteres.")
      end
      value.strip
    end

    def number!(value)
      unless value.is_a?(String) && value.match?(/\A[0-9-]{5,20}\z/)
        raise Error.new("invalid_destination", "Informe uma conta de destino válida.")
      end
      value
    end

    def digest(values)
      Digest::SHA256.hexdigest(JSON.generate(values.sort.to_h))
    end

    def rule(key, default)
      defined?(FinancialRule) ? FinancialRule.fetch_integer(key, default) : default
    end
  end
end
