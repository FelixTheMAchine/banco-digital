module Api
  module V1
    module Admin
      class LoansController < BaseController
        def index
          rows, page = paginate(Loan.order(created_at: :desc))
          render json: { loans: rows.map(&:public_json), pagination: page }
        end

        def review
          decision = { "approved" => "approve", "rejected" => "reject", "approve" => "approve", "reject" => "reject" }[params.require(:decision)]
          raise ArgumentError unless decision
          loan = Loan.find(params[:id])
          ::Credit::Applications.review!(loan: loan, admin: current_user, decision: decision, reason: required_reason!)
          render json: { loan: loan.reload.public_json }
        end
      end
    end
  end
end
