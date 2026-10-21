require "bigdecimal"

module Reports
  class Spreadsheet
    KINDS = %w[accounts transactions loans loan_analyses investment_profiles financial_report].freeze
    MAX_ROWS = 5_000
    attr_reader :kind

    def initialize(actor:, kind:, from: nil, to: nil, request_id: nil)
      raise ArgumentError unless actor.active? && actor.role == "admin" && actor.mfa_enabled?
      raise ArgumentError unless kind.is_a?(String) && KINDS.include?(kind)
      raise ArgumentError if (from.present? && !from.is_a?(String)) || (to.present? && !to.is_a?(String))
      [from, to].select(&:present?).each { |date| raise ArgumentError unless date.is_a?(String) && date.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/) }
      @actor, @kind, @request_id = actor, kind, request_id
      @from = from.present? ? Date.iso8601(from) : nil
      @to = to.present? ? Date.iso8601(to) : nil
      raise ArgumentError if @from && @to && @from > @to
      [@from, @to].compact.each { |date| raise ArgumentError unless date.year.between?(1900, 2100) }
    end

    def generate
      headers, scope, columns = definition
      scope = scope.where("created_at >= ?", @from.beginning_of_day) if @from
      scope = scope.where("created_at < ?", (@to + 1.day).beginning_of_day) if @to
      rows = scope.order(created_at: :desc).limit(MAX_ROWS + 1).to_a
      raise ArgumentError, "Reduza o período do relatório" if rows.size > MAX_ROWS
      package = Axlsx::Package.new
      workbook = package.workbook
      header_style = workbook.styles.add_style(bg_color: "103C3D", fg_color: "FFFFFF", b: true, alignment: { horizontal: :left })
      money_style = workbook.styles.add_style(alignment: { horizontal: :right })
      export_headers = headers.each_with_index.flat_map do |header, index|
        columns[index].to_s.end_with?("_cents") ? [header, "#{header} (centavos)"] : [header]
      end
      workbook.add_worksheet(name: "Simulação") do |sheet|
        sheet.add_row export_headers, style: header_style, types: Array.new(export_headers.size, :string)
        rows.each do |record|
          values, styles, types = [], [], []
          columns.each do |column|
            monetary = column.to_s.end_with?("_cents")
            values << value_for(record, column)
            styles << (monetary ? money_style : nil)
            types << :string
            if monetary
              values << raw_value_for(record, column).to_i
              styles << nil
              types << :integer
            end
          end
          sheet.add_row values, types: types, style: styles
        end
        sheet.auto_filter = "A1:#{('A'.ord + export_headers.size - 1).chr}#{rows.size + 1}"
        sheet.sheet_view.pane do |pane|
          pane.top_left_cell = "A2"
          pane.state = :frozen_split
          pane.y_split = 1
          pane.active_pane = :bottom_left
        end
        sheet.column_widths(*Array.new(export_headers.size, 24))
      end
      bytes = package.to_stream.read
      AuditLog.create!(user: @actor, action: "admin.export.#{kind}", request_id: @request_id)
      bytes
    end

    def self.safe_text(value)
      text = value.to_s
      # Excel treats these prefixes as formulas in several import workflows.
      text.match?(/\A(?:[\t\r\n]|[[:space:]]*[=+\-@])/) ? "'#{text}" : text
    end

    private

    def definition
      case kind
      when "accounts"
        [["ID", "Cliente ID", "Conta", "Agência", "Status", "Disponível", "Bloqueado", "Criada em"],
         Account.all, %i[id user_id number branch status available_cents blocked_cents created_at]]
      when "transactions"
        [["ID", "Tipo", "Valor simulado", "Descrição", "Criada em"],
         LedgerTransaction.all, %i[id kind amount_cents description created_at]]
      when "loans"
        [["ID", "Cliente ID", "Solicitado", "Prazo", "Parcela", "Total", "Decisão", "Revisão", "Criada em"],
         Loan.all, %i[id user_id amount_cents term_months installment_cents total_cents status review_reason created_at]]
      when "loan_analyses"
        [["ID", "Cliente ID", "Solicitado", "Decisão preliminar", "Score interno", "Limite estimado", "Renda disponível", "Motivos", "Criada em"],
         Loan.all, %i[id user_id amount_cents analysis_decision internal_score estimated_limit_cents available_income_cents analysis_reasons created_at]]
      when "investment_profiles"
        [["ID", "Cliente ID", "Perfil", "Score educativo", "Classes educativas", "Alertas", "Criado em"],
         InvestmentProfile.all, %i[id user_id profile score recommendation_classes profile_warnings created_at]]
      else
        [["ID", "Cliente ID", "Conta", "Status", "Disponível", "Bloqueado", "Limite diário", "Criada em"],
         Account.all, %i[id user_id number status available_cents blocked_cents daily_limit_cents created_at]]
      end
    end

    def raw_value_for(record, column)
      case column
      when :analysis_decision
        record.eligibility_snapshot["eligible"] ? "Elegível em simulação" : "Não elegível em simulação"
      when :internal_score, :estimated_limit_cents, :available_income_cents
        record.eligibility_snapshot[column.to_s]
      when :analysis_reasons
        Array(record.eligibility_snapshot["reasons"]).join("; ")
      when :recommendation_classes
        Array(record.recommendations).map { |item| item["asset_class"] }.compact.join("; ")
      when :profile_warnings
        Array(record.warnings).join("; ")
      else
        record.has_attribute?(column) ? record.public_send(column) : nil
      end
    end

    def value_for(record, column)
      value = raw_value_for(record, column)
      if column.to_s.end_with?("_cents")
        # Currency cells are formatted text to avoid Excel's binary floating-point conversion.
        whole, fraction = value.to_i.abs.divmod(100)
        digits = whole.to_s.reverse.scan(/.{1,3}/).join(".").reverse
        return "#{value.to_i.negative? ? '-' : ''}R$ #{digits},#{fraction.to_s.rjust(2, '0')}"
      end
      return self.class.safe_text(value.utc.strftime("%d/%m/%Y %H:%M UTC")) if value.respond_to?(:utc)
      self.class.safe_text(value)
    end
  end
end
