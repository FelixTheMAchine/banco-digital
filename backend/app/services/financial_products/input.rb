require "bigdecimal"
require "bigdecimal/util"

module FinancialProducts
  module Input
    MAX_CENTS = 9_000_000_000_000_000
    module_function

    def integer(value, label, min: 0, max: MAX_CENTS)
      unless value.is_a?(Integer) && value.between?(min, max)
        raise Error, "#{label} deve ser um inteiro entre #{min} e #{max}."
      end
      value
    end

    def decimal(value, label, min:, max:)
      unless value.is_a?(String) && value.match?(/\A-?[0-9]{1,4}(?:\.[0-9]{1,6})?\z/)
        raise Error, "#{label} deve ser uma string decimal exata."
      end
      number = BigDecimal(value)
      raise Error, "#{label} está fora dos limites da simulação." unless number.between?(BigDecimal(min.to_s), BigDecimal(max.to_s))

      number
    end

    def text(value, label, min: 1, max: 2000)
      raise Error, "#{label} inválido." unless value.is_a?(String) && value.strip.length.between?(min, max)

      value.strip
    end

    def choice(value, allowed, label)
      raise Error, "#{label} inválido." unless allowed.include?(value)

      value
    end
  end
end
