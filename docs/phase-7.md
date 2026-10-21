# Checkpoint — Fase 7: segurança e administração

## Entrega implementada

- MFA TOTP de seis dígitos (RFC 6238), com intervalo de 30 segundos, tolerância somente ao passo anterior e rejeição de códigos já utilizados.
- Segredos TOTP e de cadastro pendente protegidos por Active Record Encryption. Produção exige três chaves próprias fornecidas pelo ambiente; desenvolvimento deriva as chaves do `SECRET_KEY_BASE` local e testes usam chaves exclusivas de teste. O setup gera um segredo local aleatório; não utilize fallbacks de desenvolvimento ou chaves de teste em ambiente público. O cadastro pendente expira em dez minutos.
- Oito códigos de recuperação de uso único, devolvidos uma vez e persistidos apenas como resumos SHA-256 de valores aleatórios com 128 bits de entropia cada. A posse de um código de recuperação não substitui a senha no login.
- Login exige segundo fator quando habilitado. Refresh preserva a data da confirmação anterior, sem transformar a rotação de tokens em confirmação MFA recente.
- Confirmação adicional válida por cinco minutos para administração e operações bancárias de risco. Ativação de MFA revoga as outras sessões; desativação exige senha e segundo fator e revoga todas. Administradores não podem desativar o próprio MFA.
- Papéis administrativos somente por provisionamento local interativo. Cadastro público não permite escolher o papel. Toda operação administrativa exige conta ativa, papel administrativo, MFA e sessão recentemente confirmada.
- Administração de clientes, contas, movimentações, alertas, empréstimos, auditoria e regras. Revisões de crédito têm justificativa e preservam a análise original. Não há endpoint para editar saldos.
- Bloqueios de contas passam pelo serviço bancário auditável. Mudanças de regras financeiras usam chaves permitidas, inteiros positivos, limites explícitos e versões.
- Exportação XLSX de contas/saldos, movimentações, empréstimos, análises, perfis e relatório de saldos; filtros de período, cabeçalhos formatados, datas legíveis e auditoria.

## Arquivos

`backend/db/migrate/20261020000006_add_security_and_admin.rb`, `backend/app/models/financial_rule.rb`, `backend/app/services/security/`, `backend/app/services/reports/`, `backend/app/controllers/api/v1/security/`, `backend/app/controllers/api/v1/admin/`, `backend/lib/tasks/admin.rake` e testes novos em `backend/spec/`. Os serviços de autenticação e o controller de login também foram modificados.

## Fluxo de MFA

Após autenticar, envie `POST /api/v1/security/mfa/enrollment` com `password`. O resultado contém `secret` e `provisioning_uri`, destinados ao aplicativo autenticador. Envie um código em `POST /api/v1/security/mfa/enable` com `code`. Guarde os `recovery_codes` em local seguro; não serão exibidos novamente.

Um código TOTP utilizado na ativação não pode ser reutilizado imediatamente no login. Aguarde o próximo intervalo ou utilize um código de recuperação. Login aceita `otp_code` ou `recovery_code` além de e-mail e senha. Confirmação adicional usa `POST /api/v1/security/mfa/verify` com `code` ou `recovery_code`.

Um reset de senha não desativa o MFA. Perda do autenticador e de todos os códigos de recuperação depende de recuperação assistida e verificação humana, não implementada automaticamente.

## Provisionamento administrativo local

Cadastre um cliente fictício, confirme o e-mail e habilite MFA. Depois, em um terminal interativo local:

```bash
docker compose run --rm api bundle exec rails admin:create
```

O comando solicita o e-mail do cliente existente e a confirmação `PROMOVER`. Exige cliente ativo, verificado e com MFA; revoga as sessões anteriores e registra auditoria. Entre novamente com senha e segundo fator. Não fornece senha ou segredo em argumentos de processo. Em produção, substitua esse provisionamento manual por processo formal com menor privilégio e aprovação revisada.

## Exportação

`GET /api/v1/admin/exports.xlsx?kind=accounts&from=2026-01-01&to=2026-12-31` exige administrador com confirmação MFA recente. Tipos permitidos: `accounts`, `transactions`, `loans`, `loan_analyses`, `investment_profiles` e `financial_report`.

O limite é de 5.000 linhas; períodos maiores devem ser reduzidos. Textos com prefixos de fórmula são neutralizados e as células são explicitamente texto. Valores monetários são formatados em reais a partir de centavos inteiros, como texto monetário, evitando a conversão implícita para ponto flutuante do Excel. Cada valor também tem uma coluna de centavos inteiros para cálculos exatos dentro do limite numérico do Excel. As células com a apresentação em reais são texto. Nenhum relatório exporta senhas, tokens, segredos MFA ou CPF completo.

## Concorrência e falhas

MFA bloqueia usuário e sessão antes de alterar controles de segurança e verifica novamente propriedade, validade, revogação e status. Um logout ou uma desativação anterior ao bloqueio impede a alteração; confirmar MFA não reativa sessões revogadas. Recuperação e OTP são consumidos sob o mesmo bloqueio. A administração verifica novamente o papel e a sessão dentro da transação; bloqueios bancários respeitam a ordem determinística dos usuários envolvidos.

Erros de relatórios, filtros, regras desconhecidas e decisões inválidas retornam respostas controladas. Falhas do banco fazem rollback das mudanças e da auditoria correlata. A geração de XLSX é limitada e ocorre em memória.

## Verificação

Foram escritos testes de criptografia de segredos, senha atual, ativação, expiração de cadastro, replay TOTP, uso único de recuperação, revogação, login MFA, preservação do step-up no refresh, restrições administrativas, exportação e fórmulas. A quantidade coletada e os resultados reais devem ser registrados no checkpoint final de validação; este documento não afirma execução sem evidência.

Para executar:

```bash
docker compose run --rm test bundle exec rspec spec/services/security spec/services/spreadsheet_spec.rb spec/requests/mfa_authentication_spec.rb spec/requests/admin_access_spec.rb
```

## Limites e revisão humana

São referências de verificação OWASP ASVS, API Security Top 10 e MASVS para o cliente móvel. MFA, criptografia e testes não constituem auditoria ou certificação de banco. A operação de produção ainda exige revisão independente, TLS e proxies confiáveis, gestão e rotação das chaves de criptografia, proteção de Redis/filas, retenção LGPD, restauração de backups e resposta a incidentes. A chave de criptografia não deve mudar sem um plano de rotação que preserve a leitura dos segredos existentes.


## Validação integrada final

Os cenários deste módulo integraram a suíte completa aprovada em Docker; consulte comandos, resultados atuais e limites no [checkpoint final da Fase 8](phase-8-validation.md).
