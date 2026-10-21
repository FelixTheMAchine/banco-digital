# Checkpoint — Fase 5: investimentos educativos

Implementados questionário, classificação explicável, reserva de emergência, carteira educativa, comparação de oito classes, simulações de aportes, cenários de perda e ganho e objetivos financeiros. Não há compra, venda, custódia ou transferência de dinheiro para investimentos.

## Arquivos principais

- `backend/db/migrate/20261020000005_create_investments.rb` e modelos `InvestmentProfile`, `InvestmentSimulation` e `FinancialGoal`.
- `backend/app/services/investments/{products,profiler,simulator,portfolio_simulator}.rb`.
- Controllers de perfil, produtos, simulações e objetivos em `backend/app/controllers/api/v1/`.
- `backend/spec/services/investments_spec.rb` e cenários de API/isolamento em `backend/spec/requests/financial_products_spec.rb`.

## Questionário e adequação educativa

`POST /api/v1/investment_profile` recebe:

```json
{
  "answers": {
    "risk_tolerance": "medium",
    "knowledge": "intermediate",
    "horizon_months": 60,
    "liquidity_need": "medium",
    "emergency_reserve_cents": 1200000,
    "goal": "Reserva para planos futuros",
    "monthly_contribution_cents": 20000
  }
}
```

Tolerância e liquidez aceitam `low`, `medium` e `high`; conhecimento aceita `beginner`, `intermediate` e `advanced`. O prazo é de 1 a 600 meses. O resultado inclui `profile` (`conservative`, `moderate`, `aggressive`), score educativo, respostas, motivos, riscos, liquidez e alertas.

A classificação considera prazo, conhecimento, liquidez, estoque de dívidas e capacidade financeira. Reserva incompleta, prazo inferior a um ano, liquidez alta ou ausência de renda disponível restringem a carteira a uma referência conservadora de liquidez. O salário não determina sozinho a classificação. Iniciantes não são classificados como arrojados somente por declarar tolerância alta.

A reserva-alvo é de seis meses de despesas declaradas, ou doze quando não há salário fixo cadastrado. A prestação de dívidas é presumida pelo estoque dividido em 24 meses, com aviso explícito. O capital disponível para estudar novos investimentos é o saldo disponível da conta menos a reserva ainda faltante, sem movimentar ou reservar valores reais. O questionário alerta quando um aporte declarado excede a renda disponível.

As classes são Tesouro Selic, Tesouro IPCA+, CDB, LCI/LCA, fundos de renda fixa, fundos imobiliários, ETFs e ações. Cada produto identifica taxa **fictícia**, risco, liquidez e limitações. Carteiras diversificadas somam 100% e explicam por que cada classe aparece. O catálogo não usa dados de mercado nem promete retorno.

## Simulação de valor e aportes

`POST /api/v1/investment_simulations` recebe:

```json
{
  "initial_amount_cents": 100000,
  "monthly_contribution_cents": 10000,
  "months": 60,
  "annual_rate_percent": "10.0"
}
```

O valor inicial e cada aporte devem ser inteiros entre zero e 100.000.000 centavos. A taxa é uma string decimal entre `-20` e `50`, permitindo estudar perdas. O prazo é limitado a 600 meses. Projeções que ultrapassem a representação segura de centavos são rejeitadas.

A taxa anual efetiva fictícia é convertida para taxa mensal com `BigDecimal`/`BigMath`, sem `Float`. Há arredondamento mensal em centavos e aportes no fim do mês. O resultado separa valores aportados de ganhos ou perdas e fornece projeção mensal e cenários adverso, base e favorável, com taxas três pontos percentuais abaixo e acima da base. Esses cenários não têm probabilidade associada. Não incluem impostos, taxas, inflação, mudanças de mercado ou garantias.

`GET /api/v1/investment_simulations` lista as 100 simulações mais recentes do cliente; `GET /api/v1/investment_simulations/:id` exige propriedade. As simulações salvas preservam seu resultado e não executam aplicações.

## Carteira diversificada

O mesmo endpoint aceita `allocations` em vez de `annual_rate_percent`:

```json
{
  "initial_amount_cents": 100001,
  "monthly_contribution_cents": 10001,
  "months": 60,
  "allocations": [
    { "product_id": "tesouro-selic", "allocation_percent": 55 },
    { "product_id": "etf", "allocation_percent": 45 }
  ]
}
```

São aceitas de uma a oito classes distintas, com percentuais inteiros positivos que somem exatamente 100%. Os identificadores vêm de `GET /api/v1/investment_products` e também aparecem nas recomendações do perfil.

O cálculo projeta cada ativo separadamente pela sua taxa fictícia, aloca novos aportes nos percentuais informados e soma os saldos mensais. Não há rebalanceamento do patrimônio acumulado. Centavos indivisíveis são distribuídos por maiores restos; a soma das partes preserva integralmente cada aporte. A taxa anual média exibida serve apenas para comparação inicial, sem substituir os cálculos por ativo. O resultado guarda alocações, projeção, cenários e premissas em `portfolio`.

## Objetivos financeiros

`GET/POST /api/v1/financial_goals` e `PATCH/DELETE /api/v1/financial_goals/:id` operam somente no escopo do proprietário. O corpo de criação/atualização é `{financial_goal: {name, target_cents, target_date, status}}`. A meta deve ter valor positivo em centavos, nome de 3 a 120 caracteres e data válida. Estados: `active`, `completed`, `cancelled`. Metas são planejamento; não criam saldo ou reserva contábil. Alterações são auditadas.

## Verificações e limites

Os testes cobrem reserva antes de risco, restrição por liquidez e prazo, capacidade financeira, diversificação, taxas fictícias, contribuições a taxa zero, cenários negativos, valores fracionários, estouro de projeção, conservação dos centavos por ativo, alocações inválidas e isolamento de clientes.

```bash
bash scripts/test.sh spec/services/investments_spec.rb spec/requests/financial_products_spec.rb
```

No PowerShell, use `./scripts/test.ps1` com os mesmos caminhos. Consulte o relatório final para os testes efetivamente executados.

A metodologia é educativa, autodeclarada e simplificada. Não constitui análise profissional de suitability, recomendação personalizada certificada, previsão ou garantia de rentabilidade. Auditoria, revisão regulatória, riscos de mercado reais, tributação e dados autorizados são condições de uma eventual etapa futura.


## Validação integrada final

Os cenários deste módulo integraram a suíte completa aprovada em Docker; consulte comandos, resultados atuais e limites no [checkpoint final da Fase 8](phase-8-validation.md).
