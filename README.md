# Lanchonete API — Luan e Pedro

API REST em Dart para gerenciamento de cardápio e pedidos de uma lanchonete.

## Funcionalidades
- Cadastro e login de clientes com senha armazenada em hash SHA-256 com salt e token Bearer em tabela de sessões; logout.
- Perfis `customer` e `admin`.
- Categorias e produtos (CRUD de produtos).
- Pedidos com vários itens, observações, retirada ou entrega.
- Cálculo do subtotal, taxa e total no servidor.
- Status do pedido e status do pagamento.
- Resumo administrativo de vendas e produtos mais pedidos.
- SQLite persistente, chaves estrangeiras e transação ao criar pedido.
- Endpoint de documentação em `/docs`.

## Requisitos
- Dart SDK 3.3 ou superior.

## Executar
```bash
dart pub get
dart run bin/server.dart
```
Servidor: `http://localhost:8080`

Variáveis opcionais:
```bash
PORT=8080 DATABASE_PATH=lanchonete.db dart run bin/server.dart
```

## Teste rápido
1. Abra `GET http://localhost:8080/health`.
2. Cadastre um cliente em `POST /auth/register`:
```json
{"name":"Cliente Teste","email":"cliente@email.com","password":"senha1234"}
```
3. Cadastre um produto como administrador. Para o projeto acadêmico, promova uma conta diretamente no SQLite:
```sql
UPDATE users SET role='admin' WHERE email='cliente@email.com';
```
Faça login novamente para receber token e use `Authorization: Bearer TOKEN`.
4. Crie categoria (`POST /categories`) e produto (`POST /products`):
```json
{"name":"Hambúrgueres","description":"Lanches"}
```
```json
{"name":"X-Burger","description":"Pão, carne e queijo","category_id":1,"price_cents":2590,"available":true}
```
5. Crie pedido (`POST /orders`):
```json
{
  "customer_name":"Maria",
  "customer_phone":"49999999999",
  "order_type":"pickup",
  "payment_method":"pix",
  "notes":"Retirar no balcão",
  "items":[{"product_id":1,"quantity":2,"notes":"Sem cebola"}]
}
```

## Dinheiro
Valores monetários são enviados e armazenados em centavos. Exemplo: R$ 25,90 = `2590`.
Isso evita erros comuns de arredondamento com ponto flutuante.

## Rotas
Consulte `GET /docs` para a lista completa de endpoints e enums.

## Observações importantes de segurança
Este projeto é uma base acadêmica funcional, não uma implantação pronta para produção.
O mecanismo de autenticação é didático e deve ser reforçado antes de uso real. Recomenda-se:
- hash de senha com Argon2id ou bcrypt (o exemplo usa SHA-256 com salt, insuficiente para produção);
- tokens de sessão com expiração automática, rate limiting e rotação;
- validação de entrada mais rigorosa, rate limiting e HTTPS;
- autorização por pedido/cliente consistente;
- criação de usuário administrador por fluxo seguro;
- logs sem dados sensíveis e backups do banco.

## Estrutura
```text
lanchonete_api/
├── bin/server.dart
├── lib/src/app.dart
├── lib/src/database.dart
├── lib/src/security.dart
├── test/api_test.dart
├── pubspec.yaml
└── README.md
```
