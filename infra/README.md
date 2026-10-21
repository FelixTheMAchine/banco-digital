# Infraestrutura local e preparação operacional

O Compose inicia PostgreSQL 17, Redis 7, API Rails, worker Sidekiq, scheduler e web Next.js. O backend usa Ruby 3.4.11/Debian Trixie com cliente PostgreSQL 17; o schema SQL preserva funções e triggers. Web usa imagem Node com saída standalone. O aplicativo Expo é iniciado separadamente, conforme [mobile/README.md](../mobile/README.md).

## Iniciar, verificar e parar

Bash, na raiz:

```bash
bash scripts/setup.sh
bash scripts/test.sh
docker compose ps
docker compose logs --follow api worker scheduler
docker compose stop
```

PowerShell:

```powershell
.\scripts\setup.ps1
.\scripts\test.ps1
docker compose ps
docker compose logs --follow api worker scheduler
docker compose stop
```

Scripts criam segredos locais aleatórios quando `.env` não existe e preservam um arquivo existente. Se a política Windows impedir scripts, use os comandos Compose documentados no README ou uma política apenas para o processo conforme as regras da máquina. Não publique `.env` nem saída completa de `docker compose config`, que pode conter credenciais interpoladas.

Serviços padrão: web `http://localhost:3000`, API `http://localhost:3001`, PostgreSQL 5432 e Redis 6379. Web, PostgreSQL e Redis são publicados em loopback; a API usa `API_BIND_HOST=127.0.0.1` por padrão. Portas são ajustáveis no `.env`. Se mudar a porta web, ajuste também links de e-mail e origens relacionadas.

`GET /up` é liveness Rails. `GET /api/v1/health` consulta PostgreSQL e Redis; indisponibilidade retorna 503. O worker processa e-mails/agendamentos e o scheduler recupera vencidos a cada 30 segundos usando lease Redis. Um processo saudável não comprova correção de todos os fluxos.

## Banco, testes e reconciliação

O serviço `test` usa `banco_digital_test`, separado do banco de desenvolvimento. O boot de teste exige nome terminado em `_test`; nunca use um banco com dados que deseja preservar. `pg_dump`/`psql` precisam ser compatíveis com PostgreSQL 17 para carregar/salvar `db/structure.sql`.

```bash
docker compose run --rm test bundle exec brakeman --no-pager
docker compose run --rm test bundle exec bundler-audit check --update
docker compose exec api bundle exec rails banking:reconcile
docker compose exec api bundle exec rails banking:dispatch_scheduled
```

Reconciliação lê o livro-razão, detecta divergências e bloqueia contas afetadas para revisão, sem alterar lançamentos. O despacho manual é uma ferramenta operacional; o scheduler já executa a recuperação automática. Duplicidade de fila não pode duplicar a movimentação.

Volumes persistem com `stop`. `docker compose down --volumes` apaga os dados: não o use como correção automática. Backups/restauração exigem uma política própria; testes isolados de crash não substituem um ensaio de recuperação de desastre.

## Acesso mobile na rede de testes

Em aparelho físico, configure a API com IP LAN exato em `API_BIND_HOST` e inclua-o em `APP_HOSTS`; o mobile usa `EXPO_PUBLIC_API_URL` com esse mesmo IP/porta. Recrie a API após mudar o Compose. Android Emulator normalmente usa `10.0.2.2`, incluído no allowlist de desenvolvimento; iOS Simulator usa localhost do Mac.

Use somente rede confiável, controle o firewall e mantenha PostgreSQL/Redis em loopback. Não publique o backend de desenvolvimento ou Metro na internet. Release mobile exige HTTPS e credenciais de assinatura próprias; não basta que um bundle JavaScript seja gerado.

## Proxy e certificados de build

Dockerfiles aceitam opcionalmente secret BuildKit `proxy_ca` para uma CA fornecida pelo ambiente. Exemplo no ambiente gerenciado:

```bash
docker build --secret id=proxy_ca,src="$CODEX_PROXY_CERT" -t banco-digital-backend:development backend
docker build --secret id=proxy_ca,src="$CODEX_PROXY_CERT" -t banco-digital-web:development web
```

O certificado não é copiado para camadas da imagem. Uma estação local comum não precisa dessa opção. Mantenha proxy/CA configurados e a verificação TLS ativa; não use `--insecure` ou desabilite validação para contornar erros.

## Produção e staging

O Compose padrão fixa Rails em desenvolvimento. Alterar apenas `RAILS_ENV` no `.env` não o converte em produção. `.env.production.example` é inventário de configuração sem segredos, não uma implantação pronta. A imagem backend fornecida inclui ferramentas/dependências de desenvolvimento; uma imagem operacional reduzida e revisada deve ser preparada para exposição pública.

Antes de staging compartilhado/produção:

- Defina TLS, DNS, hosts/origens exatos e URLs HTTPS de frontend/e-mail. BFF precisa de `API_URL` acessível pelo servidor e `WEB_ORIGIN` exata; cookies sem Secure só são permitidos em HTTP loopback local.
- Forneça `SECRET_KEY_BASE` exclusivo e três chaves Active Record Encryption por gerenciador de segredos, com rotação/recuperação testadas. Não grave esses valores em imagens, logs ou Git.
- Separe papéis PostgreSQL de migração/aplicação. A aplicação não deve criar bancos/roles, alterar schemas ou desabilitar triggers. A imagem local cria um administrador de cluster por conveniência de desenvolvimento, inadequado à operação pública.
- Use PostgreSQL remoto com validação de certificado/identidade (`sslmode=verify-full`) e Redis remoto protegido (`rediss://`, CA e autenticação). Não desative validação TLS.
- Configure SMTP autenticado com STARTTLS obrigatório e validação de certificado. Homologue limites, retries e retenção. Desenvolvimento grava mensagens privadas em `backend/tmp/mails`.
- Restrinja logs, filas e backups. Jobs de instruções recebem e-mail/finalidade; o token nasce no worker e aparece apenas na entrega. E-mails continuam sendo dados pessoais mesmo sem token nos argumentos Redis.
- Revise proxies confiáveis, limites por IP, CSP e coordenação distribuída de refresh antes de usar múltiplas réplicas web.
- Teste restauração consistente de dados/schema/chaves, RPO/RTO, monitoramento, resposta a incidentes e controles ASVS/API Top 10/MASVS.
- Reavalie os avisos de dependência mobile ainda sem correção upstream antes de processar material de assinatura ou distribuir builds.

Veja [security.md](../docs/security.md), [arquitetura](../docs/architecture.md) e os [resultados de validação](../docs/phase-8-validation.md). Nenhum procedimento local autoriza dinheiro real ou substitui revisão regulatória e instituições autorizadas.
