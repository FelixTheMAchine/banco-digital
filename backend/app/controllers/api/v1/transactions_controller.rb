module Api
  module V1
    class TransactionsController < BankingBaseController
      PAGE_SIZE = 20

      def index
        page = pagination_page!
        scope = own_account.ledger_transactions
        if params[:type].present?
          type = params[:type]
          raise Banking::Error.new("invalid_filter", "Tipo de operação inválido.", status: :bad_request) unless %w[deposit withdrawal transfer reversal].include?(type)
          scope = scope.where(kind: type)
        end
        from = filter_date!(:from, Date.current - 30)
        to = filter_date!(:to, Date.current)
        raise Banking::Error.new("invalid_filter", "O período deve ter até 366 dias e estar em ordem.", status: :bad_request) if to < from || (to - from).to_i > 366
        scope = scope.where(completed_at: from.beginning_of_day...((to + 1).beginning_of_day))
        count = scope.count
        transactions = scope.order(completed_at: :desc, id: :desc).offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
        render json: { transactions: transactions.map { |item| item.public_json(account: own_account) },
          pagination: { page: page, total_pages: (count + PAGE_SIZE - 1).div(PAGE_SIZE), total_count: count } }
      end

      def show
        render json: { transaction: own_transaction.public_json(account: own_account) }
      end

      def receipt
        render json: { receipt: own_transaction.receipt_json(account: own_account) }
      end

      def reverse
        transaction = Banking::Operations.reverse!(**operation_options, transaction: own_transaction)
        render json: { transaction: transaction.public_json(account: own_account) }, status: :created
      end

      private

      def own_transaction
        @own_transaction ||= own_account.ledger_transactions.find(params[:id])
      end

      def pagination_page!
        value = params.fetch(:page, "1").to_s
        raise Banking::Error.new("invalid_page", "Página inválida.", status: :bad_request) unless value.match?(/\A[0-9]{1,6}\z/) && value.to_i.positive?
        value.to_i
      end

      def filter_date!(key, default)
        return default unless params[key].present?
        raise ArgumentError unless params[key].is_a?(String)
        Date.iso8601(params[key])
      rescue ArgumentError
        raise Banking::Error.new("invalid_filter", "Use datas no formato AAAA-MM-DD.", status: :bad_request)
      end
    end
  end
end
