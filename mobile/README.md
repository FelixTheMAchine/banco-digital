# Aurora mobile — Android e iOS

Aplicativo React Native com Expo SDK 58, React 19.3 e TypeScript. Ele usa a API Rails do monorepo; não substitui dados financeiros quando o servidor está indisponível. Todos os valores são fictícios.

## Iniciar no VS Code

Use Node.js 24.19 ou outra versão compatível (22.13+, 24.3+). Inicie primeiro API, PostgreSQL, Redis, worker e scheduler seguindo o README da raiz.

No PowerShell, a partir da raiz:

```powershell
Set-Location mobile
Copy-Item .env.example .env
npm ci
npm start
```

Em Bash/WSL:

```bash
cd mobile
cp .env.example .env
npm ci
npm start
```

Configure `EXPO_PUBLIC_API_URL` no `.env`, sem `/api/v1` ao final. Reinicie o Metro após alterá-la. Abra o QR com Expo Go compatível com SDK 58 ou use um build próprio. `npm run android` e `npm run ios` abrem simuladores já instalados; o simulador iOS exige macOS/Xcode.

| Ambiente | URL de desenvolvimento |
| --- | --- |
| Android Emulator padrão | `http://10.0.2.2:3001` |
| iOS Simulator no mesmo Mac da API | `http://localhost:3001` |
| Aparelho físico | `http://IP_LAN_DO_PC:3001` |

No aparelho físico, `localhost` aponta para o próprio celular. PC e aparelho precisam alcançar a mesma rede. O Compose publica a API em loopback por padrão. Em uma rede local confiável, configure **no `.env` da raiz** `API_BIND_HOST` com o IP LAN exato do PC e inclua esse IP em `APP_HOSTS`; configure o mesmo endereço no `.env` mobile. Reinicie o serviço API. Libere somente a porta da API no firewall da rede de desenvolvimento; preserve PostgreSQL e Redis em loopback. Não utilize uma rede pública nem exponha o backend de desenvolvimento à internet.

## Fluxos disponíveis

- Cadastro fictício, confirmação/reenvio de e-mail, recuperação/redefinição de senha e login com MFA ou código de recuperação.
- Abas Início, Movimentar, Planejar, Investir e Perfil; modo claro/escuro segue o sistema.
- Conta, abertura, bloqueio preventivo e encerramento de conta vazia; depósitos/saques simulados, transferências confirmadas, agendamentos e cancelamento de operações elegíveis.
- Extrato com filtros/paginação, comprovantes e estornos compensatórios. Transferências concluídas não podem ser canceladas pelo cliente; somente depósitos/saques próprios elegíveis em até 24 horas admitem estorno.
- Empréstimos Price, comparação de prazos, score interno explicado, solicitações, decisões e contestação de rejeições, sem desembolso real.
- Questionário de investidor, classes de ativos, projeções, aportes, cenários, carteira sugerida e histórico de simulações.
- Atualização cadastral, objetivos, notificações, MFA TOTP, códigos de recuperação, confirmação adicional e revogação de sessões.

O painel administrativo permanece separado na aplicação web. O aplicativo não oferece edição arbitrária de saldos. Tokens de e-mail podem ser copiados das mensagens em `backend/tmp/mails` para as telas de confirmação/recuperação. Não os coloque em logs ou capturas compartilhadas.

## Credenciais, concorrência e falhas

Access e refresh tokens ficam no `expo-secure-store`, com acessibilidade local do dispositivo e backup desabilitado. O cliente serializa a renovação e as escritas de credenciais. Respostas antigas de refresh/logout não podem restaurar uma sessão encerrada ou apagar um novo login. Não há gravação de tokens em AsyncStorage nem logs de credenciais.

A biometria é um bloqueio local opcional, reaplicado ao ir para segundo plano. Usa biometria forte com fallback para credencial do aparelho quando suportado; sempre há a opção de encerrar a sessão e entrar novamente com senha. Esse bloqueio não substitui MFA no servidor. Face ID deve ser validado em build próprio; Expo Go não oferece todas as capacidades nativas.

Movimentações persistem a chave de idempotência no armazenamento seguro **antes** do envio. Falha de rede, resposta de sucesso ilegível ou erro 5xx preserva a chave para nova tentativa do mesmo pedido, inclusive após reiniciar. Há no máximo oito pedidos sem confirmação; o app bloqueia novos pedidos em vez de descartar chaves antigas. Confira o extrato antes de repetir uma operação de resultado incerto. O backend continua responsável por saldo, limites, propriedade e consistência.

Há timeout, erros visuais, confirmações e recuperação de falhas React. Exportação JavaScript bem-sucedida não comprova ausência de crashes nativos.

## Verificar e preparar builds

```bash
npm run typecheck
npm test
npx expo install --check
npx expo-doctor
npm run export
```

`npm run export` gera bundles Hermes Android/iOS em `dist/`; eles não são APK, AAB ou IPA assinados. O [checkpoint](../docs/phase-6.md) registra verificações efetivas.

O `app.config.ts` exige origem HTTPS válida quando `APP_VARIANT=production`, remove exceções HTTP do release, mantém backups Android desabilitados e não habilita atualizações OTA. Variáveis `EXPO_PUBLIC_*` são públicas no bundle: nunca coloque segredos nelas.

Para uma exportação release no PowerShell, use sua API HTTPS de testes:

```powershell
$env:APP_VARIANT = 'production'
$env:EXPO_PUBLIC_API_URL = 'https://sua-api-de-testes.example'
npm run export
```

Em Bash:

```bash
APP_VARIANT=production EXPO_PUBLIC_API_URL=https://sua-api-de-testes.example npm run export
```

Para builds EAS, configure conta Expo, projeto e URL HTTPS antes de executar:

```bash
npx eas-cli@latest login
npx eas-cli@latest build:configure
npx eas-cli@latest build --profile development --platform android
npx eas-cli@latest build --profile development --platform ios
npx eas-cli@latest build --profile production --platform android
npx eas-cli@latest build --profile production --platform ios
```

O perfil development gera APK Android ou app iOS para simulador; preview gera APK de teste interno; production prepara AAB Android e iOS de distribuição. Configure `EXPO_PUBLIC_API_URL` HTTPS no ambiente EAS de preview/production. Conta, identificadores definitivos, certificados, provisionamento e contas das lojas são necessários. Esta entrega não publica aplicativos e não afirma que binários nativos foram compilados/assinados.

## Revisões pendentes

Testar Android/iOS físicos, instalação e retomada após encerramento do processo, perda de rede durante operação, teclado, leitor de tela, biometria/PIN, alteração de biometria, SecureStore, revogação remota e screenshots no alternador de apps. Revisar MASVS e as dependências antes de distribuir. Consulte o checkpoint para alertas de dependências ainda sem correção upstream.
