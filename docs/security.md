# Segurança, evidências e riscos abertos

Aurora é uma fintech **simulada**, sem dinheiro real. Há controles implementados e testes, mas não certificação bancária, ASVS/MASVS ou garantia de segurança absoluta. Os resultados executados estão nos [checkpoints](roadmap.md) e na [Fase 8](phase-8-validation.md); um arquivo de teste ou um build não comprova comportamento em produção ou em dispositivos físicos.

## Controles implementados

| Área | Controle |
| --- | --- |
| Autenticação | Argon2id, e-mail verificado, access opaco de 15 minutos, refresh de 30 dias, rotação/revogação e detecção de replay |
| Recuperação | Tokens com hash, propósito separado, expiração, uso único e respostas de instruções genéricas |
| MFA | TOTP, segredo criptografado, passo monotônico contra replay, recuperação aleatória de uso único, sessão revalidada sob lock |
| Autorização | Escopo do cliente, listas explícitas de campos, atribuição pública sem privilégios, administrador com MFA e confirmação recente |
| Web | BFF, cookies HttpOnly/SameSite, Secure em HTTPS/produção, origem exata e cabeçalho CSRF em mutações, leitura de corpo limitada |
| Mobile | SecureStore, refresh serializado, proteção contra respostas antigas, idempotência durável e bloqueio biométrico local opcional |
| Motor financeiro | Centavos inteiros, ACID, locks ordenados, idempotência, constraints diferíveis, razão imutável, reconciliação e estorno compensatório |
| Fraude | Limites diários/por operação, valor elevado, comparação com histórico, rejeições repetidas/cooldown e revisão auditada |
| Relatórios | Papel+MFA, período/volume limitado, colunas permitidas, texto protegido contra fórmulas e auditoria da exportação |
| Operação local | Origens/hosts explícitos, portas restritas por padrão, segredos fora do Git e logs filtrados |

Senhas não usam SHA-256: esse hash é reservado a credenciais aleatórias de alta entropia. O servidor verifica estado do usuário/sessão e TTL, em vez de confiar no que a interface apresenta. Sessões revogadas não podem ser reativadas por uma resposta antiga de refresh. MFA de acesso não elimina a confirmação recente de cinco minutos exigida para ações de risco/administração.

As verificações de concorrência incluem perda real da conexão PostgreSQL entre débito e crédito e confirmação de rollback completo, além de duplicidade, saldo insuficiente e bootstrap concorrente. Isso cobre o caso ensaiado; não substitui recuperação após falha de disco, indisponibilidade prolongada, corrupção ou desastre.

## Fronteiras de confiança e dados

PostgreSQL é a autoridade persistente. Interfaces, filas, Redis e parâmetros não autorizam saldo, propriedade ou decisão financeira. Queries usam Active Record/parametrização; trechos SQL fixos do motor não interpolam entradas arbitrárias. Não há upload ou fetch de URL fornecida pelo cliente implementados: qualquer adição exige revisão específica de malware, SSRF e command injection.

Dados devem ser fictícios. CPF válido por checksum não comprova identidade e pode coincidir com número real. Dados pessoais cadastrados não recebem criptografia de campo generalizada; o segredo MFA sim. Volumes, backups, transporte e acesso ao PostgreSQL precisam ser protegidos antes de receber informação real. Desativação não apaga o ledger nem satisfaz sozinha direitos de eliminação/LGPD.

A trilha de auditoria é append-only nas operações normais e não armazena credenciais/payload completo. Um administrador do banco ainda pode desabilitar triggers ou executar DDL; o Compose local usa privilégios administrativos por conveniência. Produção precisa separar credenciais de migração/aplicação e limitar os privilégios de ambas, além de preservar evidências fora do alcance de alterações comuns.

## Segredos, e-mail e logs

`.env`, chaves, tokens, links e e-mails locais ficam fora do Git. Produção exige `SECRET_KEY_BASE` exclusivo e três chaves próprias de Active Record Encryption; rotação, recuperação e guarda dessas chaves precisam de procedimento testado. Perdê-las pode impedir a leitura dos segredos MFA.

Verificação/recuperação gera token dentro do worker e entrega pelo canal de e-mail; ele não entra nos argumentos Redis. A fila ainda contém e-mails. Entregas em `backend/tmp/mails` contêm credenciais utilizáveis e devem ser privadas/removidas quando não necessárias. Não compartilhe capturas de matrícula MFA, recuperação ou mensagens de teste.

Logs Active Job/mailer/SQL foram desabilitados nos ambientes configurados; parâmetros sensíveis e textos pessoais são filtrados. O handler Sidekiq registra classe da falha sem copiar contexto completo. Revise proxies, ferramentas de observabilidade, crash reporters e novas integrações: esses controles não tornam público o conteúdo da fila ou da máquina.

## Riscos web e limites de autenticação

O BFF usa origem exata, `X-Aurora-CSRF: 1` e bloqueio de `Sec-Fetch-Site: cross-site` nas mutações. CORS é uma restrição de navegador, não autenticação de API. Não guarde tokens em localStorage. A exceção de cookies sem Secure é restrita a HTTP loopback explicitamente configurado; não estenda isso para LAN ou produção pública.

A coordenação de refresh do BFF é por processo, com resultado válido agrupado por três segundos e tamanho limitado. Antes de múltiplas réplicas, implemente coordenação distribuída ou desenho equivalente. A CSP atual contém `unsafe-inline` por compatibilidade com a saída Next; revise nonces e políticas mais restritas antes de publicação. Proteção CSRF e HttpOnly não eliminam XSS.

Recuperação e reenvio de confirmação retornam mensagem genérica. Cadastro distingue sucesso/falha de unicidade e conserva risco de enumeração; diferenças de tempo, carga e bloqueio por identidade também requerem revisão. Limites por IP dependem da confiança correta em proxies encaminhadores; não aceite `X-Forwarded-For` arbitrário.

## Alertas móveis ainda sem correção upstream

A atualização controlada para Expo SDK 58 e patches compatíveis reduziu o relatório observado para **15 avisos high**, derivados dos dois problemas abaixo, sem moderate/critical naquela execução. Eles não são 15 vulnerabilidades independentes do código bancário.

| Pacote/caminho | Aviso e situação observada |
| --- | --- |
| `braces` 3.0.3 via Metro → metro-file-map → micromatch | GHSA-vfj7-8cjw-p6xm: esgotamento de pilha em padrões profundamente aninhados; a versão estável mais recente consultada continuava afetada |
| `node-forge` 1.4.0 via Expo CLI → code-signing-certificates | GHSA-86w9-cpqp-85rv: validação permissiva de assinatura PKCS#1; a versão estável mais recente consultada continuava afetada |

Esses caminhos pertencem às ferramentas de build/desenvolvimento; o código de negócio não importa esses pacotes. Isso limita exposição, mas não resolve os avisos. Não exponha Metro à internet nem processe projetos, padrões ou material de assinatura não confiáveis. Reavalie os avisos, o alcance real e a cadeia de assinatura antes de distribuir. Não houve uso de `npm audit fix --force`, supressão do relatório ou fork sem revisão para aparentar ausência de vulnerabilidades. O [checkpoint mobile](phase-6.md) contém a evidência correspondente.

## Produção, release e controles humanos

O Compose padrão é de desenvolvimento e não deve ser publicado como arquitetura de produção. Uma implantação exige TLS ponta a ponta apropriado, SMTP com STARTTLS obrigatório/validação de certificado, origens/hosts controlados, banco com menor privilégio, Redis autenticado/protegido, backup restaurável, alertas e resposta a incidentes. `GET /up` e `/api/v1/health` não constituem auditoria.

Bundles Android/iOS não são APK/AAB/IPA assinados nem comprovam ausência de crashes nativos. Não foram validados aparelhos, biometria/PIN, SecureStore sob mudanças de biometria, suspensão/retomada, leitores de tela ou distribuição por lojas. Isso exige dispositivos, toolchains e credenciais próprias. Não há certificados privados ou conta Apple/Expo embutidos no projeto.

OWASP ASVS, API Security Top 10 e MASVS orientam esta revisão, sem declaração de conformidade. Antes de exposição pública/distribuição:

- [ ] Atualizar modelo de ameaças, inventário de dados e classificação das integrações.
- [ ] Revisar autenticação, MFA, recuperação, replay, entropia e rotação de todas as credenciais.
- [ ] Executar testes manuais de BOLA/IDOR, mass assignment, papéis e enumeração em todas as rotas.
- [ ] Testar refresh entre réplicas, proxies confiáveis, CSP/nonces, CSRF, XSS, rate limiting e falhas de Redis.
- [ ] Resolver ou registrar tratamento formal dos avisos de dependência abertos, com nova consulta aos bancos de avisos.
- [ ] Revisar logs, filas, e-mails, backups, relatórios e observabilidade para exposição de dados.
- [ ] Verificar privilégios PostgreSQL, imutabilidade operacional, TLS, chaves e restauração consistente.
- [ ] Executar testes físicos Android/iOS, assinatura, acessibilidade, lifecycle, biometria e armazenamento seguro segundo MASVS.
- [ ] Ensaiar incidentes, reconciliação, perda de fila, recuperação de desastre, RPO/RTO e monitoramento.
- [ ] Definir base legal, retenção, anonimização/descarte e atendimento LGPD compatível com preservação contábil.
- [ ] Obter revisão independente de segurança e operação, documentando riscos aceitos e pendências.

Não habilite movimentações financeiras reais sem homologação, análise regulatória e integração com instituições autorizadas. Nenhum resultado desta simulação equivale a licença bancária ou sistema 100% seguro.
