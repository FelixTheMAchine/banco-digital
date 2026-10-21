# ADR 0001 — Monólito modular e fronteira de simulação

Status: adotada; decisão inicial preservada e atualizada após implementação dos módulos web, mobile e financeiro.

## Contexto

O projeto precisa funcionar localmente no VS Code, atender web e Android/iOS e demonstrar consistência financeira sem dinheiro real. Identidade, autorização e o livro-razão devem permanecer verificáveis no backend, com falhas e concorrência testáveis.

## Decisão

Adotar monorepo com Rails API modular, PostgreSQL como fonte de verdade e Redis para filas, limites e lease do scheduler. Next.js atende a web por BFF; Expo atende mobile com SecureStore. O motor bancário permanece em uma transação PostgreSQL, evitando introduzir consistência distribuída antes de validar o domínio.

Usar tokens opacos com hashes persistidos e revogação no servidor. O access dura 15 minutos; refresh rotativo dura 30 dias por emissão e preserva a família para detectar replay. Não usar JWT autocontido como substituto da verificação de estado. MFA TOTP protege login/ações sensíveis; seu segredo é criptografado e códigos de recuperação são de uso único.

Criar contas digitais e contábeis juntas. Nenhum endpoint administrativo edita saldo arbitrariamente: partidas dobradas, idempotência, locks, checks e triggers preservam consistência, e estornos elegíveis são compensatórios. Clientes não desfazem transferências concluídas unilateralmente.

Manter crédito e investimentos como produtos educativos: premissas e taxas fictícias explícitas, decisões explicáveis, revisão/contestação e nenhuma execução financeira externa. Validar cada fase com checkpoint e registrar separadamente o que foi implementado, executado e ainda exige validação externa.

## Consequências

Autenticação consulta PostgreSQL para verificar usuário/sessão; índices, rate limiting e operação do banco acompanham o crescimento. Web não disponibiliza tokens ao JavaScript: BFF usa cookies HttpOnly e proteção de origem/CSRF. Mobile serializa refresh e persiste credenciais em armazenamento seguro. A coordenação de refresh atual é local ao processo web e exige evolução antes de escalar horizontalmente.

A fronteira ACID simplifica consistência, mas não elimina falhas de infraestrutura, necessidade de reconciliação, restauração e auditoria. Triggers não substituem menor privilégio nem protegem contra administrador irrestrito do banco. O Compose local facilita desenvolvimento, sem constituir implantação de produção.

Builds e testes automatizados não certificam segurança, MASVS ou produção. Alertas ainda abertos, limites de CSP/escala, dispositivos físicos, assinatura/distribuição e controles humanos ficam registrados em [segurança](../security.md) e nos [checkpoints](../roadmap.md). Operações reais exigem uma etapa posterior de homologação, análise regulatória e instituições autorizadas.
