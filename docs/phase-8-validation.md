# Checkpoint final — Fase 8: validação e entrega

Esta entrega contém as implementações das fases 1 a 7 e a validação disponível da Fase 8. É uma **fintech de simulação**. Os resultados abaixo foram executados; assinatura/publicação nativa, auditoria independente e implantação pública continuam sendo fronteiras externas explícitas.

## Resultados executados

| Área | Comando/verificação | Resultado |
| --- | --- | --- |
| Backend | `docker compose run --rm test` | **155 exemplos, zero falhas**, Ruby 3.4.11, Rails 8.1.4, PostgreSQL 17 |
| Concorrência/crash | Conexões PostgreSQL independentes; `pg_terminate_backend` exatamente entre débito e crédito | Rollback completo; saldos, lançamentos e reconciliação preservados |
| Jobs reais | Scheduler, Sidekiq e recuperação de senha em containers | E-mail de desenvolvimento entregue; transferência agendada concluída, débito e crédito de um centavo conferidos |
| Reconciliação | Corrupção privilegiada controlada do cache em banco de teste, restaurando o trigger antes da revisão | Bloqueio e evidências persistem sem alterar valores ou lançamentos |
| API/SAST | `bundle exec brakeman --no-pager` | Zero avisos e zero erros no relatório consultado |
| Gems | `bundle exec bundler-audit check --update` | Nenhuma vulnerabilidade conhecida reportada no snapshot consultado |
| Docker | Build das imagens API/web, migrations e seis serviços em execução | API, web, PostgreSQL e Redis saudáveis; worker e scheduler iniciados |
| Queda do Redis | Redis encerrado com SIGKILL; saúde e login consultados durante a indisponibilidade | Ambos retornam JSON HTTP503; nenhum token é emitido; recuperação volta a HTTP200 |
| Web | `npm run typecheck`, `npm test`, `npm run build` | TypeScript/build aprovados; sete testes unitários aprovados |
| Web/navegador | Playwright Chromium contra API e web em containers | Três testes aprovados; nenhum erro de página observado |
| Web/dependências | `npm audit --omit=dev` | Zero alertas reportados |
| Mobile | `npm run typecheck`, `npm test` | TypeScript aprovado; 34 testes aprovados |
| Mobile/configuração | `npx expo install --check`, `npx expo-doctor --verbose` | Compatibilidade aprovada após patches; Doctor 20/20 |
| Mobile/bundles | `APP_VARIANT=production EXPO_PUBLIC_API_URL=https://api.example.test npm run export` | Bundles Hermes Android e iOS gerados com HTTPS de exemplo |
| Mobile/dependências | `npm audit --json` | **15 alertas high**, sem moderate/critical, derivados de dois problemas upstream ainda sem correção estável |
| Contrato/arquivos | YAML/JSON/Bash, links e referências OpenAPI | 55 caminhos, 68 operações documentadas; referências internas resolvidas |

Os resultados estruturados estão em [validation-summary.json](validation-summary.json). O histórico da primeira entrega, quando o runtime estava bloqueado, permanece no checkpoint da Fase 1 e não representa o estado atual.

## Fluxos verificados no navegador

Login com cookies HttpOnly/SameSite e sem tokens em localStorage; rotação concorrente de refresh; origem externa rejeitada; depósito confirmado; extrato e comprovante; transferência entre duas contas fictícias; Price/CET; simulação de investimentos; perfil, notificações e segurança; acesso administrativo negado ao cliente; administração autorizada com TOTP e download XLSX; navegação móvel em 390px sem overflow; foco de diálogo e confirmação de desativação sem executar a desativação. Todos usam a API real, sem fallback de saldo no frontend.

Uma captura da interface real com dados fictícios está em [dashboard-preview.png](dashboard-preview.png). Não se inventou histórico anterior à abertura da conta para preencher o gráfico.

## Correções encontradas pela execução

- Normalização de CPF corrigida para não produzir intervalo inválido de caracteres no Ruby.
- Defaults financeiros opcionais tratados sem aceitar strings monetárias fornecidas pelo cliente.
- SQL do saldo histórico qualificado para evitar ambiguidade em joins.
- Conta de compensação inicializada com segurança após schema load e sob concorrência.
- Revalidação de sessão/MFA dentro do bloqueio financeiro; sessão revogada não autoriza operação em andamento.
- Retries idempotentes preservados após mudança de limite ou passagem da data agendada.
- Bloqueio/encerramento e classificação do saldo bloqueado preservam o total contábil; não existe edição arbitrária de saldos.
- Falha de crédito, perda de conexão, corrida de saques, transferências opostas e estorno concorrente não deixam movimento parcial.
- Reconciliação consegue registrar bloqueio não financeiro mesmo quando encontra cache corrompido por uma intervenção fora dos controles normais.
- Corpos sem Content-Length, inclusive DELETE, são limitados; JSON malformado é rejeitado antes do parser Rails registrar credenciais.
- Job de agendamento bloqueia usuários antes da linha agendada; cancelamento concorrente e jobs duplicados têm cobertura com transações realmente commitadas.
- Sidekiq 7 fixado em `connection_pool ~> 2.5` (resolvido 2.5.5): a versão 3 interrompia sua thread de agendamento. O build agora também falha imediatamente se a instalação de gems falhar.
- Queda do limitador Redis responde 503 com erro genérico e mantém as operações fechadas.
- Dependências atualizadas para Rails 8.1.4, Puma 8.0.2, Ruby 3.4.11 e Expo 58.0.17; os dois avisos Puma e o alerta EOL Rails encontrados inicialmente foram eliminados.
- Foco de diálogos web, concorrência do refresh e persistência das intenções financeiras mobile foram corrigidos e cobertos por testes.

## Bloqueio de distribuição mobile

Os 15 alertas npm são propagados por cadeias de dependências de **braces 3.0.3** (Metro/micromatch; GHSA-vfj7-8cjw-p6xm) e **node-forge 1.4.0** (Expo CLI/assinaturas; GHSA-86w9-cpqp-85rv). Não são 15 vulnerabilidades independentes na lógica de negócio. As versões estáveis mais recentes consultadas permaneciam afetadas.

O projeto não ocultou esses alertas nem aplicou forks criptográficos sem revisão. O job `mobile_dependency_security` do GitHub Actions falha explicitamente em high/critical e preserva o relatório. **O workflow completo não deve ser apresentado como verde nem o release mobile como liberado enquanto esse bloqueio existir.** Mantenha o toolchain em ambiente confiável, sem Metro público ou material de assinatura não confiável. Veja [phase-6.md](phase-6.md) e [security.md](security.md).

## Limites materiais

- Bundles Hermes não são APK, AAB ou IPA. Gradle/Xcode, assinatura, distribuição, Expo/EAS e contas Apple/Google não foram executados/configurados com credenciais reais.
- Aparelhos físicos, biometria, PIN, SecureStore, acessibilidade nativa e retomada de processo exigem validação Android/iOS real; não houve certificação MASVS.
- PowerShell foi revisado, mas não executado em Windows. GitHub Actions foi configurado e seus comandos principais foram exercitados localmente; não houve execução remota do workflow.
- Não houve deploy público ou configuração de DNS/certificados/SMTP reais. A preparação está em [deployment.md](deployment.md).
- Scanners e testes não substituem auditoria humana. CSP com nonces, coordenação distribuída de refresh antes de múltiplas réplicas, backups/restauração, retenção/LGPD, observabilidade e operação precisam de revisão.
- Não há dinheiro, investimentos, crédito desembolsado ou consultas de score reais. O sistema não é 100% seguro nem certificado como banco.

## Executar no VS Code

PowerShell na raiz:

```powershell
.\scripts\setup.ps1
.\scripts\test.ps1
```

Bash/WSL2:

```bash
bash scripts/setup.sh
bash scripts/test.sh
```

A web usa http://localhost:3000 e a API http://localhost:3001 por padrão. A validação neste workspace utilizou portas 3100/3101 para coexistir com processos de teste, sem alterar os defaults entregues. Configure seu próprio DEMO_PASSWORD para a carga opt-in, conforme o README; nenhuma credencial de execução privada é incluída no arquivo de entrega.
