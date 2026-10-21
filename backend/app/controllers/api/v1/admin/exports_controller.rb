module Api
  module V1
    module Admin
      class ExportsController < BaseController
        def show
          report = ::Reports::Spreadsheet.new(actor: current_user, kind: params.require(:kind),
            from: params[:from], to: params[:to], request_id: request.request_id)
          bytes = report.generate
          send_data bytes, type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            filename: "aurora-#{report.kind}-#{Date.current.iso8601}.xlsx", disposition: "attachment"
        end
      end
    end
  end
end
