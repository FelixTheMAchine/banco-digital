# Guia Windows: baixar, iniciar e testar o Aurora

Este roteiro usa **Windows, PowerShell, VS Code e Docker Desktop**. Você executará a aplicação web no navegador do próprio PC, com API, PostgreSQL e Redis em containers. Não precisa instalar Ruby ou Node para esse primeiro teste.

**Todo saldo é fictício.** Use somente dados e senhas de teste. O código não movimenta dinheiro real, não faz Pix e não compra investimentos.

## 1. Instalar o necessário

Instale estas ferramentas pelos sites oficiais:

| Ferramenta | Onde instalar | Para que serve |
| --- | --- | --- |
| WSL2 | [Guia Microsoft](https://learn.microsoft.com/en-us/windows/wsl/install) | Permite ao Docker usar o ambiente Linux no Windows |
| Docker Desktop | [Instalação para Windows](https://docs.docker.com/desktop/setup/install/windows-install/) | Executa os serviços e suas dependências |
| VS Code | [Instalação para Windows](https://code.visualstudio.com/docs/setup/windows) | Abre a pasta e oferece o terminal para os comandos |

Confira os requisitos atuais do Docker para sua edição do Windows e a virtualização do computador. Se ainda não tem WSL, abra **PowerShell como administrador** e siga o guia Microsoft; o comando inicial é:

```powershell
wsl --install
```

Reinicie o PC quando solicitado e conclua a configuração da distribuição, caso ela seja aberta. Se já usa WSL, confira seu estado e atualize-o conforme necessário:

```powershell
wsl --status
wsl --update
```

Instale e abra o Docker Desktop. Use o mecanismo **WSL2** e **Linux containers**. As [orientações oficiais sobre Docker e WSL2](https://docs.docker.com/desktop/features/wsl/) ajudam se essa opção não aparecer. Aguarde o Docker informar que o mecanismo está em execução.

A instalação pode pedir privilégios administrativos; os comandos do projeto abaixo normalmente podem ser executados em um terminal comum.

## 2. Baixar e extrair o projeto

1. Abra o [repositório banco-digital](https://github.com/FelixTheMAchine/banco-digital).
2. Na página principal, clique em **Code → Download ZIP**.
3. No Explorador de Arquivos, clique com o botão direito no ZIP e escolha **Extrair tudo**.
4. Escolha uma pasta de trabalho, por exemplo `C:\Projetos`.
5. Abra a pasta extraída. O nome costuma ser `banco-digital-main`.

A pasta correta contém **`docker-compose.yml`**, `README.md`, `backend`, `web`, `mobile` e `scripts`. Se houver outra pasta com o mesmo nome dentro da primeira, entre nela. Não execute o projeto de dentro do ZIP.

Para este caminho por ZIP, instalar Git é opcional. Não é necessário baixar separadamente o backend ou o frontend.

## 3. Abrir a pasta certa no VS Code

No VS Code, escolha **Arquivo → Abrir Pasta** e selecione a pasta que contém `docker-compose.yml`.

Abra **Terminal → Novo Terminal** e selecione **PowerShell** no menu do terminal. Os comandos deste guia devem ser executados nesse terminal, não no console do navegador nem no terminal de um container.

Se precisar ajustar a pasta, troque o caminho do exemplo pelo seu:

```powershell
Set-Location "C:\Projetos\banco-digital-main"
Get-Item .\docker-compose.yml
```

O segundo comando deve encontrar o arquivo. Se disser que o caminho não existe, corrija a pasta antes de continuar. Depois de instalar ferramentas, pode ser necessário fechar e reabrir o VS Code para atualizar o `PATH`.

## 4. Conferir o Docker

Com o Docker Desktop aberto, execute um comando por vez:

```powershell
docker --version
docker compose version
docker info
```

Os dois primeiros devem mostrar as versões. `docker info` também precisa alcançar o mecanismo do Docker e mostrar informações do servidor; o projeto usa containers Linux. Se aparecer erro de conexão com o daemon, primeiro resolva a inicialização do Docker Desktop.

Use `docker compose`, com espaço. O projeto utiliza Compose v2.

## 5. Iniciar pela primeira vez

Ainda na raiz do projeto, execute:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

Esse comando libera a execução apenas do processo PowerShell iniciado; não muda a política global da máquina. Em computadores gerenciados, regras da organização podem continuar bloqueando scripts.

O script:

1. Confere Docker e Compose.
2. Cria `.env` com segredos locais aleatórios, se o arquivo ainda não existir.
3. Constrói as imagens do backend e da web.
4. Prepara o banco e inicia web, API, PostgreSQL, Redis, worker e scheduler.

Na primeira execução haverá downloads e compilação. Aguarde a conclusão sem fechar o Docker Desktop. A duração depende do computador e da rede; não há um tempo fixo. Se terminar com erro, veja a seção 14 antes de repetir operações ou apagar arquivos.

**Não copie `.env.example` por cima do `.env` criado e não troque a senha do PostgreSQL.** O setup preserva um `.env` existente; reexecutá-lo não substitui valores antigos ou incompletos.

## 6. Abrir e conferir os serviços

Execute:

```powershell
docker compose ps
```

Confira se os seis serviços estão em execução, sem reinicialização contínua. API, web, PostgreSQL e Redis possuem verificações de saúde no Compose.

Abra no navegador:

- **Aplicação:** [http://localhost:3000](http://localhost:3000).
- **Saúde da API:** [http://localhost:3001/api/v1/health](http://localhost:3001/api/v1/health).

A aplicação deve apresentar a tela de login. A saúde deve responder com JSON, sem erro 503. A página da API não é a interface do banco; use a porta **3000** para navegar.

Estes são os endereços padrão. Se você alterou portas no `.env`, utilize os valores correspondentes. Continue usando `localhost` no navegador: trocar por outro host pode fazer a proteção de origem rejeitar operações.

## 7. Criar os dois clientes fictícios de demonstração

Para o primeiro teste, use a carga opcional de Marina e Lucas. Ambos já terão e-mail confirmado e conta aberta.

No explorador do VS Code, abra **`.env` na raiz**. Se o Windows esconder arquivos com ponto, o explorador do VS Code ainda permite encontrá-lo. Altere somente estas duas linhas:

```dotenv
RUN_DEMO_SEEDS=1
DEMO_PASSWORD=<sua-senha-exclusiva-de-teste>
```

Substitua todo o texto entre `<` e `>`, inclusive os sinais, pela senha que você escolher. Ela deve ter **12 a 128 caracteres** e não pode ser uma senha pessoal. Para evitar interpretação especial no `.env`, use letras, números e hífens, sem espaços ou caracteres como `$` e `#`. Guarde a senha de forma privada: ela será usada pelos dois clientes.

Salve o arquivo e execute:

```powershell
docker compose run --rm api bundle exec rails db:seed
```

Esse comando cria os dados no banco local já iniciado. Pode terminar sem imprimir uma mensagem de sucesso; confira se não houve erro. Para consultar o código de saída imediatamente após ele:

```powershell
$LASTEXITCODE
```

`0` indica que o comando terminou com sucesso. Em uma base nova, a carga cria:

| Cliente | E-mail para login | Senha | Saldo inicial fictício |
| --- | --- | --- | --- |
| Marina Exemplo | `marina@example.test` | A senha que você escolheu | R$ 5.565,10 |
| Lucas Exemplo | `lucas@example.test` | A mesma senha escolhida | R$ 250,00 |

O saldo de Marina resulta de R$ 6.000,00 de depósito, R$ 184,90 de saque e R$ 250,00 enviados para Lucas. Essas operações já aparecem no extrato e passam pelo livro-razão.

**Depois da carga**, volte ao `.env` e deixe:

```dotenv
RUN_DEMO_SEEDS=0
DEMO_PASSWORD=
```

Salve e mantenha os serviços com a configuração atualizada:

```powershell
docker compose up -d --wait
```

Isso não apaga clientes nem muda a senha deles. Não altere `POSTGRES_PASSWORD`, URLs do banco ou `SECRET_KEY_BASE` ao limpar as duas opções de demonstração. Não publique o `.env`.

Se esses clientes já existiam, a carga não redefine suas senhas. Repetir a carga também não deve ser usado para tentar restaurar o saldo inicial: as operações têm chaves idempotentes, e seus testes anteriores permanecem registrados.

## 8. Fazer login e testar uma transferência de R$ 100,00

1. Na janela normal do navegador, abra [http://localhost:3000/login](http://localhost:3000/login).
2. Entre com `marina@example.test` e a senha escolhida. Clique em **Entrar na conta**.
3. Confira o dashboard e abra **Minha conta**. Em uma base recém-carregada, Marina terá R$ 5.565,10 disponíveis.
4. Abra uma **janela anônima/InPrivate**, para manter a sessão de Lucas separada da sessão de Marina. Uma segunda aba normal compartilha os cookies e não mantém os dois clientes isolados.
5. Na janela anônima, abra a mesma aplicação e entre com `lucas@example.test` e a mesma senha.
6. Abra **Minha conta** de Lucas e copie o **número da conta**, incluindo o dígito e o hífen exibidos. O número é gerado para sua base; não use um número inventado.
7. Volte à janela normal de Marina e abra **Transferências**.
8. Em **Número da conta de destino**, cole a conta de Lucas. Em **Valor (R$)**, digite `100,00`. Use uma descrição como `Teste entre clientes fictícios`.
9. Deixe **Agendar para outra data** desmarcado. Clique em **Revisar transferência**.
10. Confira conta e valor; clique em **Confirmar** uma única vez. A aplicação deve mostrar a confirmação e o comprovante.
11. Confira **Extrato** e **Minha conta** de Marina. Atualize também a página de Lucas para ver o crédito.

O resultado esperado, se não houve outros testes, é Marina com **R$ 5.465,10** e Lucas com **R$ 350,00**. Uma transferência concluída não pode ser cancelada unilateralmente.

Digite valores na interface em reais, como `100,00`; não digite `10000` querendo representar centavos. Em caso de timeout ou dúvida sobre o resultado, consulte o extrato antes de iniciar outra operação.

## 9. Testar depósito, saque e extrato

Na sessão normal de **Marina**:

1. Abra **Minha conta → Depósito simulado**.
2. Informe `100,00`, clique em **Revisar operação**, confira e clique em **Confirmar operação**.
3. O saldo esperado volta a **R$ 5.565,10**.
4. Abra **Minha conta → Saque simulado**.
5. Informe `20,00`, revise e confirme. O saldo esperado passa a **R$ 5.545,10**.
6. Abra **Extrato**. Confira depósito, saque e transferência, suas datas e os sinais de entrada/saída.
7. Use o filtro de tipo ou período. No ícone de comprovante da linha, consulte os detalhes; a tela também permite imprimir o comprovante.

A sequência completa em uma base nova é:

| Etapa | Marina | Lucas |
| --- | --- | --- |
| Após a carga | R$ 5.565,10 | R$ 250,00 |
| Marina transfere R$ 100,00 | R$ 5.465,10 | R$ 350,00 |
| Marina deposita R$ 100,00 | R$ 5.565,10 | R$ 350,00 |
| Marina saca R$ 20,00 | R$ 5.545,10 | R$ 350,00 |

Se você repetiu alguma operação, os saldos serão diferentes. O extrato é a referência para conferir o que ocorreu. **Bloqueio preventivo** e **Encerrar conta** não são necessários para este roteiro; o bloqueio impede novas operações e sua liberação exige administrador.

## 10. Explorar empréstimos e investimentos

Em **Empréstimos**, abra **Nova simulação**. Informe valor e prazo, execute a simulação e leia parcelas, custo total, premissas e motivos da análise. Os critérios consideram os dados financeiros fictícios do perfil. Aprovação simulada **não deposita dinheiro** nem cria contratação real.

Em **Investimentos**, responda ao questionário de perfil, confira reserva, riscos e sugestões educativas. No simulador, compare valor inicial, aportes, prazo e cenários. As taxas são fictícias e não representam promessa de rendimento; nenhuma ordem é enviada ao mercado.

Também é possível explorar notificações, perfil e modo claro/escuro. Para entender a arquitetura e os demais recursos, consulte o [relatório do projeto](relatorio-do-projeto.md).

## 11. Rodar os testes automatizados do backend

Com Docker Desktop e serviços iniciados, volte ao terminal PowerShell na raiz:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

Esse script prepara o banco **de teste separado** e executa **RSpec do backend**. Não executa os testes web, mobile ou de navegador. Aguarde o resumo e confira se há falhas; veja também `$LASTEXITCODE` imediatamente após o comando.

O checkpoint registrado na entrega contém 155 exemplos RSpec, sem falhas naquele ambiente. Isso não é um resultado automaticamente obtido no seu Windows: confirme o que seu terminal apresenta. Não altere as URLs de teste para apontar para um banco com dados que deseja preservar.

Os comandos das outras suítes e as limitações da validação estão no [README principal](../README.md) e na [Fase 8](phase-8-validation.md).

## 12. Parar e voltar a usar sem perder os dados

Para parar os serviços:

```powershell
docker compose stop
```

Os volumes e o histórico ficam preservados. Fechar a janela do VS Code não para os containers automaticamente.

Para voltar outro dia, abra o Docker Desktop, aguarde seu início, abra a mesma pasta/terminal e execute:

```powershell
docker compose up -d --wait
docker compose ps
```

Abra novamente `http://localhost:3000` e entre com a senha já escolhida. Não precisa repetir a carga. Se precisar reiniciar somente a API para diagnóstico:

```powershell
docker compose restart api
```

Reiniciar um serviço não aplica mudanças de variáveis do `.env`; para isso use `docker compose up -d --wait`. **Não use `docker compose down -v`, exclusão de volumes ou o reset do Docker como tentativa de correção:** eles podem apagar seus dados locais.

## 13. Opcional: conhecer a administração

Você não precisa de administrador para seguir os testes anteriores. Para acessar o painel administrativo com um cliente fictício:

1. Entre com esse cliente e abra **Segurança** (`/seguranca`).
2. Clique em **Ativar autenticação**, confirme sua senha e configure a chave em um aplicativo autenticador compatível com TOTP.
3. Informe o código de seis dígitos e guarde os códigos de recuperação em local privado.
4. No terminal interativo do VS Code, na raiz do projeto, execute:

```powershell
docker compose exec api bundle exec rails admin:create
```

O comando pede o e-mail do cliente e a confirmação literal `PROMOVER`. Ele exige cliente ativo, e-mail verificado e MFA ativado. A promoção revoga as sessões: faça login novamente com senha e um **novo código TOTP**, depois abra [http://localhost:3000/admin](http://localhost:3000/admin).

Revisões e exportações exigem confirmação MFA recente. Se solicitado, abra Segurança e use **Confirmar código agora**. O mesmo código TOTP não pode ser reutilizado; aguarde o próximo intervalo no autenticador. A administração não permite editar arbitrariamente os saldos.

## 14. Resolver problemas comuns

### O terminal não encontra `docker`

Confirme a instalação do Docker Desktop e reabra o VS Code. Se continuar, revise a instalação oficial e o `PATH`. O comando `docker --version` precisa funcionar antes do setup.

### Erro de daemon, WSL ou virtualização

Abra o Docker Desktop e confira WSL2/Linux containers. Consulte `wsl --status` e a documentação da seção 1. Se o Windows solicitar reinício, faça-o antes de repetir. Um `docker info` com erro de conexão indica que o mecanismo ainda não está acessível.

### `docker-compose.yml` ou `scripts\setup.ps1` não foi encontrado

Você provavelmente está na pasta externa do ZIP ou no diretório errado. Use **Arquivo → Abrir Pasta** e escolha a pasta que contém os arquivos; confira com `Get-Item .\docker-compose.yml`.

### O setup falhou ou uma tela não abre

Na raiz, execute:

```powershell
docker compose ps
docker compose logs --tail 100 api web worker scheduler
```

Para acompanhar logs novos:

```powershell
docker compose logs --follow api web
```

Pressione `Ctrl+C` para parar de acompanhar os logs; isso não para os containers. Leia a primeira falha relevante. Não compartilhe `.env`, tokens, senhas ou chaves ao pedir ajuda.

Falhas de download podem exigir corrigir rede/proxy ou espaço disponível no Docker. Depois de resolver a causa, o setup pode ser executado novamente e preserva o `.env` existente.

### Porta ocupada

O padrão usa 3000 (web), 3001 (API), 5432 (PostgreSQL) e 6379 (Redis). Se aparecer `port is already allocated` ou erro de bind, identifique o programa que usa a porta antes de encerrá-lo.

Você também pode ajustar portas no `.env`. Ao mudar `WEB_PORT`, atualize `APP_ORIGINS` e `APP_FRONTEND_URL` para a nova origem, como `http://localhost:3002`; a origem do BFF no Compose acompanha `WEB_PORT`. Depois execute `docker compose up -d --wait` e use o novo endereço. Se mudou `API_PORT`, ajuste também o endereço de saúde. Não troque as portas internas dos serviços no Compose para seguir este guia.

### PostgreSQL rejeita a senha depois de editar `.env`

O volume existente mantém a senha com a qual o banco foi criado. Alterar `POSTGRES_PASSWORD` no arquivo não altera essa senha automaticamente. Restaure o valor original, se foi uma edição acidental. Preserve os volumes e peça orientação para alterar o papel do banco se necessário.

### Marina ou Lucas não conseguem entrar

Confira e-mail, senha escolhida e se o comando `db:seed` terminou sem erro. Esses usuários não precisam receber e-mail para o primeiro login. Se já existiam, trocar `DEMO_PASSWORD` não redefine a senha deles.

Se precisar usar **Esqueci minha senha** ou testar um cadastro próprio, o worker precisa estar ativo. Em desenvolvimento as mensagens ficam em `backend/tmp/mails`, acessíveis no VS Code, sem envio a uma caixa externa. Use o link da mensagem somente em seu ambiente local e não o compartilhe.

### A transferência foi rejeitada

Confira se copiou a conta de Lucas e está operando como Marina. Origem e destino precisam ser contas distintas e ativas, com saldo suficiente; valores devem ser positivos. Valores altos ou comportamento suspeito podem exigir MFA ou gerar bloqueio temporário. Não repita rapidamente tentativas rejeitadas. Consulte o extrato se houve dúvida de conexão.

### O script continua bloqueado pela política do Windows

Use o comando com `powershell -ExecutionPolicy Bypass -File` exatamente como mostrado. Ele não contorna políticas corporativas obrigatórias; nesse caso siga a orientação do administrador da máquina, sem desativar proteções globais.

## 15. O que este primeiro teste não entrega

Este roteiro inicia a **web local**, não um site público nem um banco autorizado. O mobile tem instruções próprias em [mobile/README.md](../mobile/README.md); o repositório não inclui APK, AAB ou IPA assinados para instalar diretamente.

A entrega registrou 15 alertas altos em dependências do toolchain mobile, bloqueando sua distribuição. Assinatura, lojas, validação em aparelhos reais, revisão independente de segurança e operação pública continuam exigindo trabalho específico. Os procedimentos PowerShell foram revisados, mas não foram executados em Windows durante a validação registrada.

O [documento de segurança](security.md) e o [relatório consolidado](relatorio-do-projeto.md) explicam os limites. Use apenas dados fictícios; homologação, análise regulatória e integração com instituições autorizadas seriam uma etapa posterior para qualquer operação financeira real.
