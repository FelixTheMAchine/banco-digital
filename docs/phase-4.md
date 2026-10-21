# Checkpoint — Fase 4: empréstimos simulados

Implementado o motor de elegibilidade, cálculo Price, solicitações persistidas, parcelas demonstrativas, contestação e revisão administrativa. Uma decisão `approved` é apenas uma decisão simulada: não constitui contrato, não libera saldo e não cria movimentação contábil.

## Arquivos principais

- `backend/db/migrate/20261020000004_create_credit.rb`: regras versionadas, solicitações, parcelas e contestações; índices, chaves estrangeiras e limites no PostgreSQL.
- `backend/app/models/{credit_rule,loan,loan_installment,loan_appeal}.rb`.
- `backend/app/services/credit/{price,evaluator,applications}.rb`.
- `backend/app/controllers/api/v1/{loan_simulations,loans,loan_appeals}_controller.rb`.
- `backend/spec/services/credit_spec.rb` e cenários de isolamento em `backend/spec/requests/financial_products_spec.rb`.

## Regras e premissas

A renda mensal é salário mais outras fontes declaradas. A renda disponível desconta despesas e prestação mensal de dívidas. O estoque de dívidas cadastrado não é confundido com uma prestação: quando o cliente não informa `monthly_debt_payment_cents`, o motor divide esse estoque por 24 meses e identifica essa hipótese no resultado.

A capacidade de parcela é o menor destes limites:

1. Percentual configurado da renda, menos prestação de dívidas.
2. Percentual configurado da renda disponível, preservando margem para imprevistos.

O limite de principal é o valor presente dessa capacidade pelo prazo e taxa da simulação, limitado ainda pelo teto configurado. Não há regra de salário multiplicado por cinco.

O score interno demonstra fatores separados: renda disponível, comprometimento atual, tempo de relacionamento, saldo contábil médio observado e histórico interno de parcelas efetivamente registradas como pagas ou em atraso. Simulações criadas não contam como pagamentos. Na ausência de histórico, o sistema não inventa pagamentos, extratos ou consultas externas. Não há consulta ao Serasa, SPC ou Banco Central, nem score oficial.

As regras ficam em `CreditRule`: taxa mensal fictícia, percentuais de comprometimento e margem, prazo presumido das dívidas, limites, tempo de relacionamento e score mínimo. A configuração ativa é única. Uma alteração administrativa cria outra versão; decisões anteriores preservam o snapshot e a versão usados. Não há execução de expressões ou código vindos da configuração.

O Sistema Price usa `BigDecimal`, com centavos inteiros no cronograma. A última parcela ajusta o principal remanescente para conservar exatamente o valor financiado. Em um exemplo de R$ 1.000,00, 2% ao mês e 12 parcelas, a parcela nominal é R$ 94,56, a última é R$ 94,54 e o total é R$ 1.134,70.

O CET é explicitamente **estimado e não regulatório**: assume tarifas, seguros e tributos iguais a zero, períodos mensais uniformes e ignora pequenos efeitos do arredondamento. A taxa é fictícia e não representa uma oferta de mercado. O resultado mostra taxa mensal, taxa anual efetiva, custo total, premissas e comparação de prazos.

## API

Todas as rotas exigem autenticação. Valores monetários são inteiros em centavos; números fracionários, negativos e tipos incorretos são rejeitados. Os limites do simulador são 1 a 120 meses e R$ 10,00 a R$ 1.000.000,00, sujeitos a tetos de aprovação menores configurados nas regras.

```json
{
  "amount_cents": 100000,
  "term_months": 12,
  "monthly_debt_payment_cents": 10000
}
```

| Método e rota | Comportamento |
| --- | --- |
| `POST /api/v1/loan_simulations` | Calcula `{simulation: ...}` sem criar solicitação. |
| `POST /api/v1/loans` | Persiste solicitação e parcelas; requer `Idempotency-Key` de 8 a 128 caracteres seguros. |
| `GET /api/v1/loans` | Lista as 100 solicitações mais recentes do próprio cliente. |
| `GET /api/v1/loans/:id` | Detalhes, snapshot, cronograma e contestações do proprietário. |
| `POST /api/v1/loans/:loan_id/appeals` | Recebe `{reason: "..."}` de 10 a 2.000 caracteres para contestar rejeição. |

Repetir a chave e o mesmo pedido devolve a solicitação existente. Reutilizar a chave com outros dados gera `409`. Uma decisão preliminar elegível entra em `pending_review`; uma inelegível entra em `rejected`. A contestação de rejeição solicita outra revisão, sem apagar a decisão original do snapshot.

A administração usa `Credit::Applications.review!(loan:, admin:, decision:, reason:)`, com decisão `approve` ou `reject` e justificativa obrigatória. Revisão, resolução da contestação e auditoria ocorrem na mesma transação. A autorização administrativa e o segundo fator estão no módulo da Fase 7. Não existe endpoint de desembolso.

## Verificações e limites

Foram escritos testes para cálculo conhecido, taxa zero, conservação do principal, valores fracionários, capacidade insuficiente apesar de salário elevado, hipóteses de dívida, regras versionadas, idempotência, contestação, revisão, rollback de auditoria e isolamento de clientes.

Execução local, com as dependências da fundação iniciadas:

```bash
bash scripts/test.sh spec/services/credit_spec.rb spec/requests/financial_products_spec.rb
```

No PowerShell, use `./scripts/test.ps1 spec/services/credit_spec.rb spec/requests/financial_products_spec.rb`. Consulte o relatório final para os comandos realmente executados neste ambiente; a presença dos testes não comprova execução.

A avaliação usa dados autodeclarados e regras demonstrativas. Taxas, capacidade, histórico, tratamento de vieses, revisão humana e eventual contratação real exigem análise independente antes de qualquer uso além de simulação.


## Validação integrada final

Os cenários deste módulo integraram a suíte completa aprovada em Docker; consulte comandos, resultados atuais e limites no [checkpoint final da Fase 8](phase-8-validation.md).
