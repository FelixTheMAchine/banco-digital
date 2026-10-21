# Checkpoint — Fase 6: aplicativo mobile

## Implementação

`mobile/App.tsx` organiza abas e telas secundárias. `src/screens/` implementa autenticação, operações bancárias, extrato/comprovantes, empréstimos, investimentos, objetivos, perfil, notificações e segurança. `src/lib/api-client.ts` centraliza HTTP, timeout, renovação serializada e proteção contra respostas antigas. `native-api.ts` integra SecureStore; `financial-intents.ts` preserva idempotência após interrupções. `money.ts` usa centavos inteiros/BigInt sem arredondamento financeiro com float.

O aplicativo consome a API real. Confirmações antecedem movimentações; o backend determina autorização, limites e consistência. Não há execução de investimentos, desembolso de crédito ou dinheiro reais. O painel administrativo está separado no frontend web.

A biometria opcional protege a apresentação local ao retomar o app, permitindo credencial do aparelho quando suportada. MFA TOTP continua no servidor. Segredos de matrícula e códigos de recuperação são apagados da tela ao ir para segundo plano.

## Versões e configuração

Atualização controlada de SDK 54 para **Expo SDK 58.0.17**, React Native 0.88.0, React 19.3.0 e TypeScript 6.0, usando a compatibilidade do Expo. Node 24.19 foi utilizado. Preserve o lockfile. PostCSS recebeu correção compatível em 8.x; UUID do gerador Xcode foi atualizado para 11.1.1, preservando a chamada `v4`, validada com 100 identificadores distintos.

`app.config.ts`, `eas.json` e `.env.example` preparam Android/iOS. Release exige HTTPS e remove exceções de transporte do desenvolvimento. Configuração nativa e assinaturas exigem validação em dispositivos e certificados próprios.

## Verificações executadas

- `npm run typecheck`: sem erros.
- `npm test`: **34 testes aprovados**, cobrindo centavos, refresh concorrente, respostas antigas, logout, credenciais inválidas, falhas de conexão, idempotência durável, reinício e pedidos de resultado incerto.
- `npx expo install --check`: dependências compatíveis com SDK 58.
- Exportação Android/iOS com production/HTTPS: bundles Hermes gerados. A primeira exportação SDK 58 concluiu em aproximadamente 39 segundos. A exportação da última revisão também foi executada após os patches compatíveis; Expo Doctor concluiu 20/20 verificações após configurar o proxy confiável do ambiente.
- `expo config --type introspect`: plugins nativos processados, configuração production sem exceção ATS de desenvolvimento.

## Segurança de dependências

Atualização SDK e correções compatíveis reduziram o relatório inicial de 35 alertas npm para **15 high**, sem moderate/critical na execução atual. Os 15 incluem dependências indiretas do mesmo conjunto de problemas; não são 15 falhas independentes do aplicativo.

| Dependência | Caminho/função | Situação observada |
| --- | --- | --- |
| `braces` 3.0.3 | Metro → metro-file-map → micromatch; análise de padrões no build/desenvolvimento | GHSA-vfj7-8cjw-p6xm, esgotamento de pilha por padrões profundamente aninhados. Versão estável mais recente consultada ainda afetada. |
| `node-forge` 1.4.0 | Expo CLI → code-signing-certificates; processamento de certificados/assinaturas | GHSA-86w9-cpqp-85rv, verificação permissiva PKCS#1. Versão estável mais recente consultada ainda afetada. |

Esses caminhos pertencem ao toolchain; o código de negócio não importa braces/node-forge. Não exponha Metro à internet nem processe projetos/padrões/material de assinatura não confiáveis. Exploração e confiança de certificados exigem revisão antes de distribuição. Não foram usados `npm audit fix --force`, forks sem revisão ou supressão do relatório para aparentar ausência de alertas.

## Limites da validação

Não foram executados simuladores, aparelhos físicos, compilação Gradle/Xcode, assinatura ou publicação. APK/AAB/IPA dependem de toolchain nativo/EAS e contas/certificados. Biometria, PIN, screenshots, acessibilidade nativa e SecureStore exigem testes reais. Não há certificação MASVS nem garantia de ausência de crashes.

Comandos Windows, rede LAN e builds estão em [mobile/README.md](../mobile/README.md).
