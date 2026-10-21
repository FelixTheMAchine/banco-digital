# Verificações automatizadas

O workflow `ci.yml` separa as evidências funcionais do bloqueio de dependências:

| Job | Verificação |
| --- | --- |
| `backend` | Banco isolado, autoload Rails, RSpec, concorrência/crash, Brakeman e bundler-audit |
| `web` | TypeScript, testes, build Next e audit das dependências de produção |
| `mobile` | TypeScript, testes, compatibilidade Expo e bundles Hermes Android/iOS |
| `mobile_dependency_security` | Audit de todo o lockfile mobile; relatório JSON preservado mesmo quando a auditoria falha |
| `web_e2e` | Chromium com API real, cookies, operações fictícias, MFA administrativo e XLSX |

O job de segurança mobile não tem `continue-on-error` nem exclusões. Alertas high/critical conhecidos impedem que o workflow completo fique verde, mesmo quando os testes funcionais e a exportação passam. Consulte `docs/phase-6.md` e o relatório final da Fase 8 antes de distribuir; não interprete bundles JavaScript como aplicativos assinados.

`../scripts/ci-seed.rb` é executado somente por Rails runner em `RAILS_ENV=test`, com banco terminado em `_test`. Ele cria clientes fictícios e uma fixture privada de MFA dentro de `backend/tmp`, com modo 0600. Não existe endpoint de criação de administradores de teste. A fixture e os traces com credenciais não são enviados como artifacts.

O workflow não publica aplicações, não cria certificados e não efetua deploy. Dependabot propõe atualizações semanais; elas precisam passar pelas verificações e por revisão antes de serem aceitas.
