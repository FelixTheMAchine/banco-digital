module Investments
  module Products
    DISCLAIMER = "Conteúdo educativo com taxas fictícias para comparação. Não é recomendação profissional, oferta, garantia de rentabilidade ou execução de investimento. Pode haver perdas; impostos, taxas, inflação e condições reais não estão incluídos."
    LIST = [
      { id: "tesouro-selic", name: "Tesouro Selic — cenário fictício", asset_class: "Tesouro Selic", annual_rate_percent: "10.0", risk: "baixo", liquidity: "diária simulada", description: "Risco soberano e oscilação de preço; útil para estudar reserva com liquidez." },
      { id: "tesouro-ipca", name: "Tesouro IPCA+ — cenário fictício", asset_class: "Tesouro IPCA+", annual_rate_percent: "9.0", risk: "moderado", liquidity: "preço sujeito à marcação a mercado", description: "Ilustração de prazo longo e risco de venda antecipada. A taxa nominal fictícia não projeta inflação real." },
      { id: "cdb", name: "CDB — cenário fictício", asset_class: "CDB", annual_rate_percent: "10.5", risk: "baixo a moderado", liquidity: "depende do vencimento e emissor", description: "Risco de crédito do emissor; liquidez e eventual cobertura dependem das regras do produto real." },
      { id: "lci-lca", name: "LCI/LCA — cenário fictício", asset_class: "LCI/LCA", annual_rate_percent: "9.5", risk: "baixo a moderado", liquidity: "carência e vencimento simulados", description: "Risco de emissor e restrições de resgate; não pressupõe tratamento tributário futuro." },
      { id: "fixed-income-fund", name: "Fundo de renda fixa — cenário fictício", asset_class: "Fundos de renda fixa", annual_rate_percent: "9.0", risk: "baixo a moderado", liquidity: "cotização e liquidação variáveis", description: "Riscos de crédito, mercado e liquidez; taxas de administração não incluídas." },
      { id: "real-estate-fund", name: "Fundo imobiliário — cenário fictício", asset_class: "Fundos imobiliários", annual_rate_percent: "11.0", risk: "alto", liquidity: "negociação em bolsa sem preço garantido", description: "Cotas e rendimentos variam; risco imobiliário, vacância e perda de capital." },
      { id: "etf", name: "ETF — cenário fictício", asset_class: "ETFs", annual_rate_percent: "12.0", risk: "alto", liquidity: "negociação em bolsa", description: "Exposição diversificada de mercado não elimina perdas nem risco cambial quando aplicável." },
      { id: "stocks", name: "Ações — cenário fictício", asset_class: "Ações", annual_rate_percent: "14.0", risk: "muito alto", liquidity: "negociação em bolsa", description: "Risco de empresas, volatilidade e perdas relevantes; retorno não é previsível." }
    ].map(&:freeze).freeze

    module_function

    def list
      LIST.map(&:dup)
    end
  end
end
