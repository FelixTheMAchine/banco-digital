# API Aurora — contrato de integração

Base local: `http://localhost:3001/api/v1`. O contrato formal está em [openapi.yaml](openapi.yaml); ele pode ser aberto em um visualizador OpenAPI local no VS Code. Não envie tokens ou dados pessoais para visualizadores hospedados por terceiros.

A API Rails atende web e mobile, valida entradas e decide autorização, limites e resultado financeiro. Todo dinheiro é fictício. Aprovação de crédito não desembolsa recursos; simulações de investimento não executam ordens.

## Transporte, valores e respostas

`POST` e `PATCH` exigem `Content-Type: application/json`. O corpo é limitado a 32 KiB; outro tipo de conteúdo retorna 415 e excesso retorna 413. Clientes diretos usam `Authorization: Bearer <access_token>`. O navegador usa o BFF descrito abaixo, sem receber tokens utilizáveis no JavaScript.

Dinheiro usa centavos inteiros: R$ 3.000,00 é `300000`. Strings numéricas e valores fracionários não substituem inteiros monetários. O limite de representação é `9000000000000000` centavos; operações e produtos aplicam limites menores próprios. Taxas decimais são transmitidas como texto e processadas com `BigDecimal`, sem dinheiro em `float`.

Datas de filtro usam `AAAA-MM-DD`. Agendamentos exigem ISO 8601 com fuso (`Z` ou deslocamento `±HH:MM`). O backend usa UTC para períodos diários/mensais; a apresentação pode converter para o fuso do dispositivo.

Erros seguem este envelope:

```json
{"error":{"code":"insufficient_funds","message":"Saldo disponível insuficiente."}}
```

`details` é opcional: validações cadastrais retornam nomes de campos; regras de risco podem retornar motivos, amostra histórica ou janela de confirmação. Não trate o texto traduzido como identificador de negócio: use `error.code` e o status HTTP.

| Status | Significado típico |
| --- | --- |
| 400 | Parâmetro obrigatório ou formato estrutural inválido |
| 401 | Credencial/sessão inválida, expirada ou desafio MFA de login |
| 403 | Papel, conta ou confirmação adicional não permitem a ação |
| 404 | Recurso inexistente ou fora do escopo do cliente |
| 409 | Idempotência conflitante ou estado incompatível com a ação |
| 413 / 415 | Corpo excessivo / conteúdo diferente de JSON |
| 422 | Validação de domínio ou token de propósito inválido |
| 429 | Limite de requisição; observe `Retry-After` |
| 503 | Dependência ou configuração necessária indisponível |

## Identidade, perfil e sessões

Os caminhos abaixo são relativos a `/api/v1`. Instruções de confirmação/recuperação são públicas; os demais recursos pessoais exigem autenticação.

| Método e caminho | Corpo / resultado |
| --- | --- |
| `POST /auth/register` | `{user: {...}}` → 201 `{user}` sem sessão automática |
| `POST /auth/login` | `{email,password,otp_code?,recovery_code?}` → par de tokens |
| `POST /auth/refresh` | `{refresh_token}` → novo par de tokens |
| `DELETE /auth/logout` | Revoga a família atual → 204 |
| `POST /auth/email_verifications` | `{email}` → 202 genérico |
| `PATCH /auth/email_verifications` | `{token}` → confirmação de e-mail |
| `POST /auth/password_resets` | `{email}` → 202 genérico |
| `PATCH /auth/password_resets` | `{token,password,password_confirmation}` → altera senha e revoga sessões |
| `GET /me` / `PATCH /me` | Consulta / atualiza `{user}` próprio |
| `DELETE /me` | Desativa cadastro e revoga credenciais, sem apagar histórico |
| `GET /sessions` | `{sessions: [...]}` com metadados permitidos |
| `DELETE /sessions/:id` | Revoga sessão/família própria → 204 |

Cadastro exige nome, CPF de teste, nascimento de maior de idade, e-mail, telefone E.164, endereço, profissão, declaração de salário, senha e confirmação. Endereço contém `street`, `number`, `city`, `state` e `postal_code`. Nascimento deve estar entre 1900-01-01 e a data em que o cliente completa 18 anos. Senha tem 12–128 caracteres, até 512 bytes, e confirmação idêntica. Renda adicional, despesas e dívidas opcionais assumem zero quando omitidas.

```json
{
  "user": {
    "full_name": "Pessoa de Demonstração",
    "cpf": "52998224725",
    "birth_date": "1994-06-15",
    "email": "demo@example.test",
    "phone": "+5511999990000",
    "address": {"street":"Rua de Teste","number":"100","city":"São Paulo","state":"SP","postal_code":"01001000"},
    "profession": "Profissional de teste",
    "monthly_salary_cents": 500000,
    "other_income_cents": 0,
    "monthly_expenses_cents": 200000,
    "existing_debts_cents": 0,
    "password": "Senha-ficticia-local-2026!",
    "password_confirmation": "Senha-ficticia-local-2026!"
  }
}
```

Use somente dados fictícios e nunca reutilize a senha pública do exemplo. Checksum de CPF não consulta bases externas, não comprova identidade e não garante que o número não pertença a alguém.

`PATCH /me` aceita nome, telefone, endereço, profissão e os quatro campos monetários de perfil. CPF, nascimento e e-mail não são alterados por esse endpoint. Papel, proprietário, status e campos de autenticação não podem ser atribuídos por cadastro/atualização pública. A resposta própria inclui CPF mascarado, `email_verified`, `mfa_enabled` e `role` como indicador para apresentação; o papel retornado nunca autoriza a interface a agir em nome do servidor.

A desativação é recusada enquanto houver saldo disponível/bloqueado ou agendamentos pendentes. Uma conta vazia é encerrada antes da desativação. Isso não apaga lançamentos ou atende, por si só, uma política de eliminação LGPD.

Login requer e-mail verificado. Access tokens expiram em 15 minutos; cada refresh recém-emitido expira em 30 dias. Ambos são opacos e apenas seus hashes persistem no PostgreSQL. Uma renovação invalida os tokens anteriores; replay de refresh revoga a família. Clientes diretos devem serializar a renovação e substituir o par de forma conjunta.

```json
{"access_token":"<token-opaco>","refresh_token":"<refresh-opaco>","token_type":"Bearer","expires_in":900}
```

Solicitar instruções responde `{message: "Se os dados forem válidos, você receberá as instruções."}`. Confirmação expira em 24 horas e recuperação em 30 minutos. Tokens têm propósito separado, uso único e emissão nova invalida os anteriores do mesmo propósito. Em desenvolvimento, o worker entrega arquivos em `backend/tmp/mails`; os links abrem as telas web em `APP_FRONTEND_URL`. Mensagens e links contêm credenciais e devem ficar privados e fora do Git.

## MFA e confirmação adicional

| Método e caminho | Corpo / resultado |
| --- | --- |
| `GET /security` | Status MFA, códigos restantes, sessões ativas, papel e janela de confirmação |
| `POST /security/mfa/enrollment` | `{password}` → `{secret,provisioning_uri}`; matrícula pendente por 10 minutos |
| `POST /security/mfa/enable` | `{code}` → `{mfa_enabled:true,recovery_codes:[...]}` |
| `POST /security/mfa/verify` | `{code}` ou `{recovery_code}` → `{verified:true,verified_until}` |
| `DELETE /security/mfa` | Senha atual e `code` ou `recovery_code` → 204 e revogação de sessões |

TOTP usa seis dígitos e intervalos de 30 segundos. O mesmo passo de tempo não pode ser reutilizado. A ativação entrega oito códigos de recuperação de 32 caracteres hexadecimais, uma única vez; cada código é consumido atomicamente. Login usa o campo `otp_code`, enquanto confirmação adicional e desativação usam `code`. MFA ativo sem código de login produz `401` com `mfa_required`.

A ativação revoga outras sessões. A confirmação recente vale cinco minutos para ações de risco e administração; renovar o access token não estende essa confirmação. Administradores não podem desativar MFA para voltar a senha apenas.

## Contas e movimentações simuladas

| Método e caminho | Resultado |
| --- | --- |
| `GET /account` / `POST /account` | Consulta / abre a única conta do cliente |
| `POST /account/deposits` | Depósito simulado → 201 `{transaction}` |
| `POST /account/withdrawals` | Saque simulado → 201 `{transaction}` |
| `POST /transfers` | Transferência atômica → 201 `{transaction}` |
| `POST /account/block` | Bloqueio preventivo próprio |
| `POST /account/close` | Encerramento próprio, com saldos zero e sem agendamentos pendentes |
| `GET /transactions` | Extrato próprio com `page`, `type`, `from`, `to` |
| `GET /transactions/:id` | Movimentação pertencente à conta |
| `GET /transactions/:id/receipt` | Comprovante JSON, identificado como simulação |
| `POST /transactions/:id/reverse` | Estorno compensatório elegível → 201 `{transaction}` |

Depósitos e saques recebem `{amount_cents,description?}`. Transferências recebem `{destination_account_number,amount_cents,description?}`. Descrição tem até 160 caracteres. Respostas contêm UUID, tipo, valor, direção contábil relativa à conta, datas, status `posted` e referência de estorno quando houver. A conta retorna agência fictícia `0001`, número, status, saldo disponível/bloqueado e limite diário.

**`Idempotency-Key` é obrigatório** em depósitos, saques, transferências, estornos, criação de agendamentos e solicitações de crédito. Na API direta aceita 8–128 caracteres seguros (`a-z`, `A-Z`, dígitos, `_`, `.`, `:`, `-`); os clientes do projeto usam UUID. Reenvie a mesma chave e os mesmos dados quando o resultado for incerto. Mesma chave com outra intenção retorna 409. Não gere uma chave nova automaticamente após timeout/5xx: consulte o extrato e repita a intenção original.

O limite de operação, o limite diário, fundos e risco são verificados no backend. Débitos e créditos só se tornam concluídos quando a transação PostgreSQL inteira confirma. Conta bloqueada/encerrada não movimenta. Bloquear reclassifica o total disponível como bloqueado; liberação administrativa faz a operação inversa, sem mudar o total contábil.

Extrato usa páginas de 20 registros, período padrão de 30 dias e filtro máximo de 366 dias. Tipos: `deposit`, `withdrawal`, `transfer`, `reversal`. Estorno pelo cliente é restrito ao iniciador de depósito/saque simulado em até 24 horas, com fundos e limites válidos. A transação original nunca é editada. Transferência concluída não admite cancelamento unilateral do remetente.

## Agendamentos, dashboard e notificações

`GET /scheduled_transfers` lista até 100 registros próprios. `POST` recebe os campos da transferência e `scheduled_at`, com fuso, entre um minuto e um ano no futuro. Agendar não reserva saldo. Valores que exigem confirmação imediata por valor elevado não podem ser agendados; na execução, todas as regras são reavaliadas. `DELETE /scheduled_transfers/:id` cancela somente estado `pending`; operação processada retorna conflito.

O scheduler consulta vencidos a cada 30 segundos, com lease Redis, e recupera enfileiramentos perdidos. Jobs repetidos continuam protegidos pela linha persistente e pela idempotência do motor financeiro.

`GET /dashboard` retorna conta (ou `null` antes da abertura), receitas/despesas do mês, evolução contábil, movimentações recentes e alertas. `GET /notifications` lista até 100 notificações próprias; `PATCH /notifications/:id/read` marca uma como lida. Identificadores de outro cliente não concedem acesso.

## Crédito educativo

`POST /loan_simulations` recebe `{amount_cents,term_months,monthly_debt_payment_cents?}`. A resposta `{simulation}` contém capacidade de pagamento, limite estimado, razões, score interno explicado, alternativas de prazo, parcela Price, cronograma, custo total e CET anual estimado com premissas. Dívida cadastrada é um estoque: sem prestação mensal explícita, a simulação usa o prazo presumido configurado e informa a hipótese.

`POST /loans` registra uma solicitação idempotente e o snapshot das regras/decisão, sem desembolso. `GET /loans` e `GET /loans/:id` retornam histórico próprio, parcelas e revisões. `POST /loans/:loan_id/appeals`, com `{reason}` de 10–2000 caracteres, contesta uma rejeição e a devolve à revisão.

Score e taxas são demonstrativos. O CET estimado pressupõe tarifas, seguros e tributos zero e explicita os efeitos de arredondamento; não constitui CET regulatório. Não há consultas Serasa, SPC ou Banco Central.

## Investimentos e objetivos educativos

`GET /investment_products` lista oito classes com taxas fictícias, riscos e liquidez. `GET /investment_profile` consulta o perfil; `POST` recebe `{answers:{risk_tolerance,knowledge,horizon_months,liquidity_need,emergency_reserve_cents,goal,monthly_contribution_cents}}`. A resposta considera renda disponível, despesas, dívidas, reserva, conhecimento, prazo e liquidez; apresenta perfil, alocação educativa, justificativas e alertas.

`POST /investment_simulations` recebe valor inicial, aporte mensal, meses (1–600) e taxa anual fictícia em texto decimal entre -20 e 50; alternativamente, recebe `allocations:[{product_id,allocation_percent}]` somando 100%. Retorna projeções, contribuições, resultado e cenários adverso/base/favorável. `GET /investment_simulations` e `GET /investment_simulations/:id` consultam simulações próprias. Nenhuma tela executa aplicações ou garante retorno.

`GET/POST /financial_goals` e `PATCH/DELETE /financial_goals/:id` gerenciam metas próprias. Escrita usa `{financial_goal:{name,target_cents,target_date,status?}}`. Nome tem 3–120 caracteres, meta é positiva e data deve estar dentro do horizonte validado. Remover uma meta não apaga lançamentos.

## Administração e XLSX

Todos os caminhos `/admin/*` exigem papel `admin`, MFA ativo e confirmação recente de cinco minutos. O papel não é atribuído por cadastro público; a promoção interativa local está no README.

- Consultas: `GET /admin/overview`, `/users`, `/accounts`, `/transactions`, `/security_events`, `/loans` e `/audit_logs`; listas paginam por `page` e `per_page` (máximo 100).
- Contas: `POST /admin/accounts/:id/block` e `/unblock`, com justificativa. Não existe edição arbitrária de saldo.
- Revisão: `POST /admin/security_events/:id/review` e `/admin/loans/:id/review`, com justificativa; crédito aceita decisão `approved`/`rejected` (também `approve`/`reject`).
- Regras: `GET/PATCH /admin/credit_rules` usa `{config:{...}}`; `GET/PATCH /admin/financial_rules` usa `{rules:{...}}`. Somente chaves conhecidas e limites válidos, sem execução de expressões.
- Relatórios: `GET /admin/exports.xlsx?kind=...&from=AAAA-MM-DD&to=AAAA-MM-DD`. Tipos: `accounts`, `transactions`, `loans`, `loan_analyses`, `investment_profiles`, `financial_report`. Limite 5000 linhas; excesso exige reduzir o período. Há auditoria, proteção de texto contra fórmulas, valores BRL legíveis e centavos inteiros, sem hashes, tokens ou CPF completo.

## Web BFF, saúde e limites conhecidos

O navegador chama `/api/...` do Next, que encaminha para `/api/v1/...` do Rails. Login/refresh do BFF retornam somente `{authenticated:true}`; tokens ficam em cookies `HttpOnly`, `SameSite=Strict`, caminho `/api`, com `Secure` em HTTPS/produção. A exceção sem `Secure` é restrita a HTTP loopback explicitamente configurado. Mutações exigem origem exata `WEB_ORIGIN`, cabeçalho `X-Aurora-CSRF: 1` e bloqueio de `Sec-Fetch-Site: cross-site`. Não use `localStorage` para credenciais.

O BFF agrupa refresh concorrente por processo, com cache de resultado válido por três segundos e limite de entradas. Isso não coordena réplicas distintas; escalabilidade horizontal exige desenho distribuído antes da publicação. O cliente mobile serializa refresh e armazena credenciais no SecureStore.

`GET /up` verifica o processo Rails, fora do prefixo. `GET /api/v1/health` verifica PostgreSQL/Redis e retorna 503 quando falham. Nenhum endpoint de saúde certifica segurança. Solicitações de recuperação/confirmacão têm resposta genérica; cadastro ainda distingue sucesso/falha de unicidade e conserva risco residual de enumeração. Veja [segurança](security.md) e os [resultados de validação](phase-8-validation.md).
