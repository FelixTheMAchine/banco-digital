# Preparação de homologação e distribuição

Esta entrega disponibiliza código, Dockerfiles, lockfiles, verificações de CI e perfis EAS. Não cria infraestrutura pública, DNS, certificados, contas de lojas ou credenciais de assinatura. Os resultados executados estão no [relatório de validação](phase-8-validation.md); os comandos abaixo são o procedimento para o operador de um ambiente próprio.

Todo ambiente continua sendo de **simulação com dinheiro fictício**. Não habilite integrações financeiras reais sem homologação, análise regulatória e integração com instituições autorizadas.

## Ambiente local e imagem web

O `docker-compose.yml` da raiz inicia Rails em **development**. O servidor Next usa seu build de produção, mas isso não transforma o conjunto em ambiente aprovado para exposição pública. Os bancos e a API são publicados em loopback por padrão.

Para revisar a experiência local:

```bash
bash scripts/setup.sh
docker compose ps
curl --fail http://localhost:3001/api/v1/health
```

No PowerShell, use `.\scripts\setup.ps1` e `Invoke-RestMethod http://localhost:3001/api/v1/health`. A web usa `http://localhost:3000`, salvo alteração das portas no `.env`.

**Não use** `docker compose --env-file .env.staging up` como atalho para produção: o Compose local define `RAILS_ENV=development` e outras escolhas locais explicitamente.

## Configuração de uma homologação isolada com TLS

Copie `.env.production.example` para um arquivo privado como `.env.staging`, ignorado pelo Git, ou forneça os mesmos campos pelo gerenciador de segredos da plataforma. Os exemplos `.invalid` não são endereços implantados. Use apenas dados fictícios e mantenha homologação separada de qualquer sistema real.

| Configuração | Requisito |
| --- | --- |
| `RAILS_ENV` | `production`, com erros detalhados e reload desabilitados |
| `SECRET_KEY_BASE` | Valor aleatório exclusivo com pelo menos 64 caracteres; sem placeholders |
| `AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY`, `AR_ENCRYPTION_KEY_DERIVATION_SALT` | Três valores próprios, cada um com pelo menos 32 caracteres, preservados em backups seguros |
| `DATABASE_URL` | Banco exclusivo, credencial de aplicação restrita e TLS com verificação do servidor, como `sslmode=verify-full` |
| `REDIS_URL` | Instância protegida, autenticação e TLS para conexão remota (`rediss://`), com CA confiável |
| `APP_HOSTS` | Lista explícita dos hosts aceitos pela API, sem wildcard |
| `APP_ORIGINS`, `APP_FRONTEND_URL` | Origem HTTPS exata da aplicação web |
| `API_URL` | Origem HTTPS da API, alcançável pelo servidor Next e com certificado confiável |
| `WEB_ORIGIN` | Origem HTTPS exata da web, sem barra final; deve corresponder ao navegador |
| `COOKIE_SECURE` | `true`; a exceção HTTP é limitada ao loopback local |
| `SMTP_*`, `MAIL_FROM` | Provedor de homologação autorizado, autenticação própria e STARTTLS obrigatório com validação de certificado |
| `RUN_DEMO_SEEDS` | `0`; a carga demonstrativa recusa execução em Rails production |

Gere e armazene os segredos em um canal privado. Não publique a saída de comandos de geração, arquivos de ambiente, mensagens de recuperação ou dumps. Trocar as chaves de Active Record Encryption sem uma estratégia de rotação pode tornar os segredos MFA existentes ilegíveis.

O BFF da web deve alcançar a API por HTTPS em homologação. O endereço `http://api:3001` do Compose local não deve ser copiado para esse ambiente: Rails production força SSL. Não desabilite a verificação TLS para contornar certificados inválidos.

Configure o gateway para terminar TLS, encaminhar corretamente o protocolo original e substituir cabeçalhos de encaminhamento fornecidos pelo cliente. A API deve aceitar tráfego somente do caminho de rede previsto. Revise proxies confiáveis e a identificação do IP antes de depender dos limites por origem.

## Construção e preparação do banco

Os comandos a seguir criam imagens locais, sem enviá-las a um registry:

```bash
docker build -t aurora-api:homolog backend
docker build -t aurora-web:homolog web
```

O Dockerfile backend fornecido é uma base de desenvolvimento. Uma imagem pública exige revisão de dependências de build, tamanho, pacotes, usuário, permissões, geração de SBOM e fixação por digest. Utilize a imagem somente no ambiente revisado para o qual foi preparada.

Em redes que exigem CA própria, forneça-a ao BuildKit com `--secret id=proxy_ca,src=/caminho/ca.pem`; não copie certificados de sessão para camadas da imagem e não desative TLS.

Mantenha um papel migrador separado do papel de execução. O primeiro pode criar extensões, tabelas, índices, funções e triggers; o segundo deve ter apenas os privilégios necessários para executar a aplicação, sem administração da instância. Teste os privilégios contra as operações e constraints reais antes de reduzir permissões.

Com conectividade privada, credenciais de homologação configuradas e um backup restaurável, o operador pode preparar o banco em um processo único:

```bash
docker run --rm --env-file .env.staging --env-file .env.migrator.staging \
  aurora-api:homolog bundle exec rails db:migrate
docker run --rm --env-file .env.staging \
  aurora-api:homolog bundle exec rails zeitwerk:check
```

`.env.migrator.staging` também deve permanecer privado e sobrescrever somente os campos necessários, principalmente `DATABASE_URL`. Remova a credencial migradora do ambiente de execução depois da preparação. Não coloque a senha diretamente nos argumentos do shell.

## Processos e verificações de entrada

Configure os seguintes processos no orquestrador escolhido, com os mesmos segredos de criptografia, rede privada e limites de recursos:

| Processo | Comando |
| --- | --- |
| API | `bundle exec rails server --binding 0.0.0.0 --port 3001` atrás do gateway TLS |
| Worker | `bundle exec sidekiq -C config/sidekiq.yml` |
| Scheduler | `bundle exec rails runner 'Banking::Scheduler.run!'` |
| Web | `node server.js` na imagem standalone fornecida |

Não publique PostgreSQL ou Redis. Dê persistência e política de backup a ambos; as filas do Redis contêm e-mails e metadados de trabalho. Configure reinício supervisionado e monitore reinícios, jobs falhos, atraso da fila, agendamentos vencidos, erros de autenticação e eventos de segurança.

Antes de permitir acesso à homologação, confira:

```bash
curl --fail https://sua-api-de-homologacao.example/up
curl --fail https://sua-api-de-homologacao.example/api/v1/health
docker run --rm --env-file .env.staging \
  aurora-api:homolog bundle exec rails banking:reconcile
```

Os endereços devem ser substituídos pelos hosts reais configurados. Um HTTP 200 verifica disponibilidade, não segurança. Execute os fluxos de navegador, MFA, autorização, exportação e falhas com clientes fictícios, e teste restauração de backup em banco separado. A reconciliação não ajusta valores arbitrariamente; divergências exigem revisão.

O refresh concorrente do BFF é coordenado em memória por processo. Antes de operar múltiplas réplicas web, implemente e teste coordenação distribuída para a rotação. Revise também CSP com nonces, logs, retenção/LGPD, alertas e resposta a incidentes, conforme [security.md](security.md).

## Android e iOS

Os bundles JavaScript/Hermes exportados não são APK, AAB ou IPA assinados. `mobile/eas.json` oferece perfis development, preview e production; os identificadores em `app.config.ts` precisam ser confirmados para a organização que distribuirá o aplicativo.

Para preparar um release, configure uma origem HTTPS de homologação em `EXPO_PUBLIC_API_URL` e use `APP_VARIANT=production`. Essa configuração remove as exceções de transporte de desenvolvimento; variáveis `EXPO_PUBLIC_*` são públicas e não podem conter segredos.

Depois de resolver os bloqueios de segurança e configurar conta/projeto Expo, o operador pode executar:

```bash
cd mobile
npm ci
npm run typecheck
npm test
APP_VARIANT=production EXPO_PUBLIC_API_URL=https://sua-api-de-homologacao.example npm run export
npx eas-cli@latest build:configure
npx eas-cli@latest build --profile preview --platform android
npx eas-cli@latest build --profile production --platform android
npx eas-cli@latest build --profile production --platform ios
```

Android de distribuição exige keystore; iOS exige conta Apple, certificados e provisionamento. Use armazenamento de credenciais apropriado e não versione chaves de assinatura. As credenciais e publicações não foram criadas ou executadas nesta entrega.

Os alertas mobile sem correção upstream registrados na [Fase 6](phase-6.md) pertencem ao toolchain Expo/Metro e continuam sendo um bloqueio de revisão para distribuição. Não os oculte nem os trate como corrigidos porque a exportação passou. Antes do envio às lojas, teste dispositivos físicos, instalação/retomada, SecureStore, biometria/PIN, perdas de rede, acessibilidade e a referência MASVS.
