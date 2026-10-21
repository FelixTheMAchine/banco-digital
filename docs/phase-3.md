# Checkpoint — interface web Aurora

## Arquivos

`web/app/` contém rotas públicas, área autenticada, painel administrativo e BFF. `web/components/` reúne navegação, formulários, operações e gráficos. `web/lib/` implementa cliente HTTP, parsing monetário, tipos e validações de proxy. `web/tests/` e `web/e2e/` contêm testes unitários de segurança e fluxos reais de navegador. Lockfile e saída standalone integram a execução local e Docker.

## Funcionalidades

Todas as telas obrigatórias da web estão implementadas e conectadas à API: login, cadastro, confirmação e recuperação, dashboard, conta, transferências e agendamentos, extrato com filtros/comprovantes/estorno elegível, empréstimos e análise Price, investimentos e questionário/carteira/cenários/metas, perfil, segurança/MFA/sessões, notificações e administração.

Identidade original com modo claro/escuro, navegação responsiva, foco visível, link de salto, diálogos com foco e confirmação, estados de carregamento, erros controlados e gráficos acompanhados por valores/tabelas. O frontend não autoriza movimentações nem calcula saldo contábil.

## Evidências de execução

- `npm run typecheck`: passou.
- `npm test`: sete testes passaram, cobrindo CSRF/origem, caminhos de proxy, cookies, stream excessivo, UTF-8 malformado, parsing de centavos e datas inválidas.
- `npm run build`: passou, incluindo rotas estáticas e proxy dinâmico.
- `npm audit --omit=dev`: zero vulnerabilidades reportadas após atualização compatível de PostCSS e reinstalação do lockfile.
- Playwright contra API real: três cenários distintos passaram, incluindo rejeição de mutação entre origens, fluxo completo de cliente e administração autorizada com TOTP e download XLSX. O fluxo do cliente verificou cookies HttpOnly, depósito confirmado, comprovante, transferência entre duas contas fictícias, análise Price/CET, investimento, perfil, segurança, notificações, negação de administração, foco do diálogo de desativação e layout de 390 px sem overflow. Nenhum erro de página foi observado. A administração percorreu todas as listas, abriu regras e exportou um arquivo Excel usando MFA real de uma fixture privada de demonstração.

## Comandos

Veja [web/README.md](../web/README.md) para Bash, PowerShell, variáveis, Docker e E2E. O próximo checkpoint integra os cenários de navegador às verificações do backend e do aplicativo.

## Limites

O ambiente usa somente dinheiro fictício. Não houve publicação pública nem integração financeira real. Refresh concorrente entre réplicas web exige coordenação distribuída antes de escalar horizontalmente. A política CSP ainda contém `unsafe-inline` por causa da saída padrão do Next; uma implantação pública deve revisar nonces, observabilidade, configuração TLS e proteção operacional. O resultado não constitui certificação de segurança.
