module FinancialProducts
  class Error < StandardError
    attr_reader :code

    def initialize(message, code: "invalid_input")
      @code = code
      super(message)
    end
  end
end
