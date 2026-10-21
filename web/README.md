# Aurora web

Aplicação Next.js com TypeScript, Tailwind, gráficos Recharts e integração real com a API Rails. Todo dinheiro é fictício. Inclui cadastro e recuperação, dashboard, conta, transferências e agendamentos, extrato e comprovantes, crédito, investimentos, perfil, MFA, notificações e administração separada.

## Executar localmente

Com Node.js 22 ou superior e API/worker já iniciados, abra um terminal na raiz:

```bash
cd web
cp .env.example .env.local
npm ci
npm run dev
```

No PowerShell:

```powershell
Set-Location web
Copy-Item .env.example .env.local
npm ci
npm run dev
```

Abra `http://localhost:3000`. O Next lê `.env.local`; configure `API_URL` com o endereço acessível pelo servidor Next. A URL interna e os tokens não são variáveis públicas. O Compose da raiz também inclui um serviço `web`.

Para validar o build de produção local:

```bash
npm run build
npm run start
```

`WEB_ORIGIN` deve ser a origem exata usada no navegador, incluindo porta. `COOKIE_SECURE=false` só é aceito em HTTP de loopback (`localhost` ou `127.0.0.1`). Uma publicação exige HTTPS, cookies Secure e configuração operacional revisada. A aplicação gera saída standalone para Docker.

## Sessões e operações

O navegador acessa o BFF em `/api/`. O BFF entrega tokens somente por cookies HttpOnly e SameSite=Strict, limitados ao caminho `/api`; o JavaScript não recebe access/refresh tokens. Somente a preferência de tema é guardada em `localStorage`.

Mutações exigem origem exata e o cabeçalho `X-Aurora-CSRF: 1`. O proxy limita corpos a 32 KiB inclusive em streams sem Content-Length, aceita JSON e não permite segmentos que escapem da API configurada. Refresh é serializado no cliente e no processo Next; o resultado fica em memória por três segundos para absorver respostas simultâneas de abas. O Compose usa uma instância web. Uma implantação horizontal precisa de coordenação distribuída de refresh antes de adicionar réplicas.

Movimentações pedem confirmação e usam chaves de idempotência preservadas em uma nova tentativa do mesmo formulário. Depósitos/saques próprios podem ser estornados quando o backend permitir, dentro de 24 horas; transferências concluídas não podem ser canceladas unilateralmente. Agendamentos pendentes podem ser cancelados. Encerramento e desativação exigem saldos zerados e ausência de agendamentos pendentes.

MFA TOTP suporta configuração, códigos de recuperação de uso único, confirmação adicional e revogação de sessões. A administração exige autorização e MFA recente no backend. Nenhuma tela permite alterar saldos diretamente.

## Verificar

```bash
npm run typecheck
npm test
npm run build
npm audit --omit=dev
```

O lockfile fixa dependências. A versão transitiva de PostCSS do Next é substituída por uma versão 8 compatível corrigida; build e auditoria foram executados após a atualização.

Os E2E usam a API real e um cliente fictício já verificado, sem MFA, em um banco de demonstração isolado. O teste registra um depósito de R$ 5,00 e, se um destinatário for configurado, uma transferência de R$ 1,00. Não execute contra dados que deseja preservar.

```bash
npx playwright install chromium
export E2E_EMAIL=cliente-de-teste@example.test
export E2E_PASSWORD='senha-exclusiva-do-seu-ambiente'
# Opcional: outro cliente verificado, com conta ativa.
export E2E_RECIPIENT_EMAIL=destinatario@example.test
npm run test:e2e
```

No PowerShell, use `$env:E2E_EMAIL='...'` e `$env:E2E_PASSWORD='...'` no lugar de `export`. O Playwright inicia o build web local já preparado; o backend deve estar ativo em `127.0.0.1:3001`. `E2E_API_URL`, `E2E_WEB_URL` e `E2E_EXTERNAL_SERVER=1` permitem um ambiente separado.

O cenário administrativo opcional lê `E2E_ADMIN_FIXTURE`, caminho de um JSON privado fora do repositório com `email`, `password` e `secret` TOTP de um administrador já provisionado exclusivamente no banco de teste/demonstração. Ele usa o código temporário real, consulta todas as listas e baixa um XLSX auditado, sem modificar regras ou decisões. Nunca use uma conta real nem versione essa fixture.

Trace e screenshots são salvos somente em caso de falha. Mesmo em testes, esses artefatos devem ser tratados como privados. As verificações estão no [checkpoint da web](../docs/phase-3.md); nenhuma análise automatizada substitui auditoria de segurança.
