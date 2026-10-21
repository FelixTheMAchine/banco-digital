# Plano e checkpoints

A entrega foi construída por módulos, preservando os checkpoints. O estado da validação efetiva e as limitações externas estão na Fase 8; implementação não equivale a certificação financeira ou de segurança.

| Fase | Implementação | Checkpoint |
|---|---|---|
| 1 — Fundação | Rails, PostgreSQL, Docker, identidade e autenticação | [Histórico inicial](phase-1-checkpoint.md) |
| 2 — Núcleo bancário | Contas, partidas dobradas, idempotência, agendamento, reconciliação e concorrência | [Fase 2](phase-2.md) |
| 3 — Web | Next.js, BFF, dashboard, operações, acessibilidade e gráficos | [Fase 3](phase-3.md) |
| 4 — Empréstimos | Regras versionadas, capacidade, Price, CET estimado, revisão e contestação | [Fase 4](phase-4.md) |
| 5 — Investimentos | Perfil, reserva, oito classes, cenários, carteira e metas | [Fase 5](phase-5.md) |
| 6 — Mobile | Expo, navegação, API, SecureStore e biometria local | [Fase 6](phase-6.md) |
| 7 — Segurança/administração | MFA, regras, alertas, auditoria, revisão e XLSX | [Fase 7](phase-7.md) |
| 8 — Validação | Testes reais, correções, builds e preparação operacional | [Resultados finais](phase-8-validation.md) |

## Fronteiras de conclusão

A simulação local não movimenta dinheiro real. Assinatura e distribuição Android/iOS, auditoria humana independente, publicação pública com TLS e credenciais reais, licenças/contratos e homologação regulatória são etapas externas. Seus requisitos estão documentados; não são tratados como executados sem evidência.
