# Checkpoint — Fase 1

> Histórico da primeira entrega. O estado atual de todas as fases está no [checkpoint final](phase-8-validation.md).

Este checkpoint cobre somente a fundação. As fases 2 a 8 estão descritas no [roteiro](roadmap.md) e não devem ser consideradas entregues.

## Arquivos e responsabilidades

| Caminho | Responsabilidade |
| --- | --- |
| `backend/app/`, `backend/config/`, `backend/db/` | API Rails, autenticação, persistência e configuração por ambiente |
| `backend/spec/` | Testes da fundação |
| `backend/Dockerfile`, `docker-compose.yml` | Ambiente local com PostgreSQL e Redis |
| `scripts/setup.*`, `scripts/test.*` | Inicialização e testes em shell/PowerShell |
| `.github/workflows/ci.yml` | Verificações automatizadas no GitHub Actions |
| `.env.example`, `.gitignore`, `.vscode/` | Configuração de exemplo, exclusão de segredos e tarefas do VS Code |
| `README.md`, `docs/` | Instalação, arquitetura, contrato, decisões e limites |
| `web/README.md`, `mobile/README.md` | Próximas etapas, ainda sem aplicações executáveis |

## Comportamento da entrega

Cadastro e manutenção do próprio perfil; validações de identidade fictícia; senhas com Argon2id; confirmação de e-mail; recuperação de senha; sessões com access/refresh tokens opacos, expiração, rotação e revogação; trilha de eventos sem segredos. Rotas, serializers, serviços e migrations foram inspecionados para alinhar o contrato OpenAPI e o modelo de dados; os resultados de execução são registrados abaixo.

A fundação não cria contas bancárias nem processa depósitos, saques ou transferências. CPF com dígitos verificadores válidos é apenas uma entrada de teste, sem validação de identidade real.

## Evidências de validação

Resultado desta entrega: implementação criada e revisão estática concluída; a validação de execução permanece pendente. Não inferir sucesso a partir da presença de arquivos de configuração ou testes.

- Inspeção inicial: workspace vazio; Node.js e Docker CLI disponíveis; Ruby e PostgreSQL ausentes no host inicial.
- Infraestrutura: `docker compose --env-file .env.example config --quiet` e `bash -n scripts/setup.sh scripts/test.sh` concluídos com código 0. YAML do Compose, CI, Sidekiq e OpenAPI, além dos JSON do VS Code, foram parseados com sucesso.
- Documentação: 84 referências OpenAPI e 17 links locais conferidos; contrato com 11 paths e 15 operações, incluindo a saúde do Rails.
- Backend: 47 exemplos RSpec definidos, incluindo cenários parametrizados. Nenhum executado neste ambiente. Inicialização Rails, migrations, Brakeman e auditoria de dependências também não executados.
- Dependências Ruby: resolução por Bundler e geração/versionamento de `Gemfile.lock` pendentes enquanto não houver runtime utilizável.
- Docker: acesso ao socket bloqueado; imagem e containers não executados. A tentativa de instalar um runtime Ruby separado exigiu acesso de rede e foi interrompida antes de executar. Ruby, PostgreSQL e Redis não foram instalados.
- PowerShell: scripts fornecidos; execução em Windows ainda exige validação em uma máquina Windows.

## Execução no VS Code

No terminal da raiz do projeto:

```bash
bash scripts/setup.sh
bash scripts/test.sh
```

No PowerShell:

```powershell
.\scripts\setup.ps1
.\scripts\test.ps1
```

A API local usa `http://localhost:3001` por padrão. O `.env` criado pelo setup permanece local. Para acompanhar logs, use `docker compose logs --follow api worker`; não compartilhe mensagens de e-mail ou logs que contenham credenciais de teste.

## Limitações atuais

Sem interfaces web/mobile, MFA, instituições externas, motor contábil, produtos financeiros, backoffice, Excel ou certificação de produção. A infraestrutura fornecida é para a máquina de desenvolvimento. Política de retenção/LGPD, e-mail de produção, recuperação de desastre e auditoria independente seguem pendentes, conforme [security.md](security.md).

## Próxima tarefa: Fase 2

Implementar contas digitais e contábeis, transações e lançamentos imutáveis de partidas dobradas. Só então adicionar depósitos, saques e transferências simuladas, com validações no servidor, locks em ordem determinística, idempotência, limites e rollback. O checkpoint deve incluir testes de duplicidade, saldo insuficiente, falhas de banco e operações simultâneas com conexões PostgreSQL independentes.
