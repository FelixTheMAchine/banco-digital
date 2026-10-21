# Checkpoint — Fase 2: núcleo bancário simulado

Esta etapa adiciona conta, movimentações e livro-razão reais no PostgreSQL, exclusivamente com dinheiro fictício. Não existe conexão com Pix, instituições financeiras ou dinheiro real.

## Arquivos entregues

- `backend/db/migrate/20261020000003_create_banking.rb`: tabelas, índices, integridade referencial e triggers contábeis.
- `backend/app/models/{account,ledger_account,ledger_transaction,ledger_entry,transfer,scheduled_transfer,notification,security_event}.rb`.
- `backend/app/services/banking/`: abertura, entradas, saídas, transferências, estornos, histórico, reconciliação, bloqueios e agendamentos.
- `backend/app/services/fraud/assessment.rb`: regras explicáveis de limites e risco.
- Controllers de conta, extrato, transferências, dashboard, notificações e agendamentos em `backend/app/controllers/api/v1/`.
- Jobs de execução de agendamentos/reconciliação e tarefas `banking:*`.
- Specs de serviços, API e concorrência PostgreSQL em `backend/spec/`.

## Garantias implementadas

Os valores são centavos inteiros. Cada movimentação possui lançamentos de débito e crédito na mesma transação ACID. A conta do cliente é um passivo contábil; depósitos e saques simulados têm contrapartida na conta de compensação fictícia. Transferências debitam a origem e creditam o destino.

Triggers PostgreSQL diferidos verificam, no commit, que cada operação tem pelo menos dois lançamentos e que a soma dos débitos e créditos corresponde exatamente ao valor da operação. Outra constraint verifica que o saldo em cache de cada conta coincide com o livro-razão. Atualizações e exclusões de lançamentos, operações, contas contábeis e registros de transferência são recusadas pelo banco. Titular, número e agência da conta não podem ser alterados.

Os serviços bloqueiam usuários e contas em ordem determinística de UUID antes da movimentação. Usam savepoints quando chamados dentro de outras transações, para impedir que uma exceção resgatada pelo chamador preserve um débito parcial. Nenhum produto de crédito é contratado implicitamente, e saídas não podem tornar o saldo negativo.

Quando a operação vem de uma sessão HTTP, o serviço busca novamente essa sessão sob o bloqueio do usuário e valida titularidade, revogação e expiração. Uma requisição que já passou pela autenticação não pode movimentar fundos após a revogação da sessão. Jobs agendados são chamadas internas e revalidam o usuário e as contas na execução.

A conta contábil de compensação também é inicializada de modo seguro após um carregamento apenas de `structure.sql`, que não contém os dados criados por migrations. Inserções concorrentes da primeira movimentação usam a unicidade no PostgreSQL; nunca criam duas contas de compensação.

Toda movimentação exige `Idempotency-Key`, com 8 a 128 caracteres (`a-z`, `A-Z`, números, `_`, `.`, `:`, `-`). A chave é única por cliente no livro-razão. Repetir a mesma operação retorna a operação original; reutilizar a chave com dados diferentes produz HTTP 409.

Uma operação já registrada continua reconhecida se o limite configurado for reduzido depois dela. O mesmo vale para um agendamento cuja data já passou: o retry retorna o registro original, sem reinterpretá-lo como uma nova ordem nem enfileirar outra cópia.

## Operações e limites

| Operação | Rota |
| --- | --- |
| Abrir/consultar conta | `POST` / `GET /api/v1/account` |
| Depósito fictício | `POST /api/v1/account/deposits` |
| Saque fictício | `POST /api/v1/account/withdrawals` |
| Transferir | `POST /api/v1/transfers` |
| Extrato e filtros | `GET /api/v1/transactions?from=AAAA-MM-DD&to=AAAA-MM-DD&type=transfer&page=1` |
| Detalhe/comprovante | `GET /api/v1/transactions/:id` e `/:id/receipt` |
| Estorno elegível | `POST /api/v1/transactions/:id/reverse` |
| Bloqueio preventivo | `POST /api/v1/account/block` |
| Encerramento da conta vazia | `POST /api/v1/account/close` |
| Agendar/listar/cancelar | `POST` / `GET /api/v1/scheduled_transfers`, `DELETE /:id` |
| Dashboard | `GET /api/v1/dashboard` |
| Notificações | `GET /api/v1/notifications`, `PATCH /:id/read` |

O extrato usa paginação de 20 registros, aceita períodos de até 366 dias e considera as datas em UTC. Os comprovantes são JSON e estão identificados como simulação. Dados são buscados sempre no escopo da conta do usuário autenticado.

Somente o titular pode estornar seus próprios depósitos ou saques simulados, em até 24 horas. O estorno cria outra operação com lançamentos opostos, preservando o histórico, e exige saldo suficiente quando produz débito. Uma operação só admite um estorno. **Transferências concluídas não podem ser desfeitas unilateralmente pelo remetente**; isso exigiria um fluxo posterior de consentimento/revisão. Agendamentos pendentes podem ser cancelados antes da execução.

As regras iniciais são configuráveis pela administração autorizada: saída diária de 5.000.000 centavos, valor máximo por operação de 10.000.000 centavos e confirmação MFA recente para saídas a partir de 2.500.000 centavos. A confirmação vale por cinco minutos. Cinco rejeições em um minuto podem iniciar um bloqueio temporário de operações por 300 segundos. Eventos registram códigos de motivos, sem tokens ou senhas.

Há também uma regra comportamental explicável: existindo pelo menos cinco débitos históricos, uma saída de pelo menos 100.000 centavos e superior a três vezes a média inteira dos últimos vinte débitos exige confirmação MFA recente. Contas novas não recebem um histórico inventado. O motivo `unusual_vs_recent_history` é exposto no erro e registrado no evento de segurança; após a confirmação, a operação permanece registrada como atípica para revisão. Esses parâmetros comportamentais estão definidos em constantes no código; os limites absolutos continuam configuráveis no painel.

O bloqueio preventivo classifica o total do cliente como saldo bloqueado, zerando o disponível. O desbloqueio administrativo devolve esse total ao disponível. A soma dos dois saldos e todos os lançamentos contábeis permanecem iguais; a reclassificação é auditada, com os valores anteriores e posteriores no evento de segurança. O cliente não pode se desbloquear. O encerramento exige ambos os saldos zerados e ausência de agendamentos de saída pendentes; contas encerradas não podem ser reabertas.

## Agendamentos e recuperação de falhas

Agendar não reserva nem movimenta saldo. A execução revalida status, disponibilidade de saldo e limites; uma mudança posterior pode fazer o agendamento falhar sem débito. Datas devem usar ISO 8601 com fuso explícito, entre um minuto e um ano no futuro.

Valores que exigem MFA imediato não podem ser agendados, pois a autenticação atual não é uma autorização permanente para débito futuro.

O processo `scheduler` consulta agendamentos vencidos a cada 30 segundos e usa uma lease Redis para evitar despachos concorrentes. Um registro despachado pode ser recuperado após cinco minutos sem conclusão, inclusive quando a fila original foi perdida. Execução duplicada de jobs não duplica movimentações: o registro é bloqueado, e a operação usa uma chave de idempotência derivada do agendamento. Não há promessa de execução no segundo exato.

## Reconciliação

```bash
docker compose exec api bundle exec rake banking:reconcile
docker compose exec api bundle exec rake banking:dispatch_scheduled
```

A reconciliação compara o saldo em cache com os lançamentos efetivos. Em caso de divergência, bloqueia a conta e registra um evento, sem reescrever valores ou apagar histórico. Não existe ajuste arbitrário de saldos pelo painel. O dispatcher também funciona continuamente pelo serviço `scheduler` do Compose.

## Testes e verificações

Os testes acrescentados cobrem partidas dobradas, depósitos/saques, saldo insuficiente, valores inválidos, rollback quando o crédito falha, idempotência, estornos compensatórios, bloqueio, comprovantes, BOLA, constraints no banco, limites, agendamentos duplicados e recuperação de fila.

Os cenários concorrentes usam conexões PostgreSQL separadas e registros efetivamente commitados: saques concorrentes, a mesma transferência repetida, transferências em sentidos opostos e corrida entre estorno de depósito e saque. Os testes de constraints diferidas forçam `SET CONSTRAINTS ALL IMMEDIATE`, pois testes que simplesmente fazem rollback não verificam constraints de commit.

Validação executada em ambiente isolado com Ruby 3.4.7, Rails 8.1.4, PostgreSQL 17 e Redis 7.4.2:

```bash
bundle exec rails db:prepare
bundle exec rspec spec/services/banking_operations_spec.rb \
  spec/services/banking_scheduling_spec.rb \
  spec/integration/banking_concurrency_spec.rb \
  spec/requests/banking_api_spec.rb
```

Resultado final da suíte bancária: **51 exemplos, zero falhas**, seed `61856`, em 18,83 segundos. O banco dedicado `banking_verify_test` foi separado dos dados de desenvolvimento.

Um teste encerra de verdade a conexão PostgreSQL da operação financeira entre o registro do débito e o crédito, usando `pg_terminate_backend` somente no processo dedicado do teste. Depois da queda, verifica que os saldos, os lançamentos e a quantidade de operações continuam intactos e reconciliados. Esse teste passou; ele não equivale a simular perda de energia, falha de disco ou corrupção do servidor inteiro.

Na verificação, foram corrigidos um SQL ambíguo do histórico de saldos, o bootstrap da conta de compensação após schema load, retries afetados por mudança de limite/data e a validação de sessão antes da movimentação. A suíte também verificou bloqueio/reclassificação de saldos, encerramento com fundos ou agendamento pendente e a regra de transações atípicas.

## Próximas verificações operacionais

- Auditoria independente dos triggers e das permissões distintas para migration e runtime.
- Carga prolongada e falhas abruptas de PostgreSQL/Redis em infraestrutura controlada.
- Monitoramento e alertas de atraso do scheduler, divergências e filas.
- Política de retenção e revisão dos eventos de segurança, limites e justificativas administrativas.

Não use a configuração de desenvolvimento como implantação pública de uma instituição financeira.
