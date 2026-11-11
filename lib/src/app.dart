import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import 'database.dart';
import 'security.dart';

final _uuid = Uuid();
const _statuses = ['pending', 'confirmed', 'preparing', 'ready', 'out_for_delivery', 'completed', 'cancelled'];
const _payments = ['cash', 'pix', 'credit_card', 'debit_card'];
const _orderTypes = ['pickup', 'delivery'];

Response jsonResponse(Object? data, {int status = 200}) => Response(
  status, body: jsonEncode(data),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic>? bodyMap(Request request) {
  try {
    final decoded = jsonDecode(request.context['body'] as String? ?? '');
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) { return null; }
}

Middleware _bodyMiddleware() => (inner) => (request) async {
  final body = await request.readAsString();
  return inner(request.change(context: {...request.context, 'body': body}));
};

int? _int(dynamic value) => value is int ? value : int.tryParse('$value');
String? _str(dynamic value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

Handler createApp(AppDatabase database) {
  final db = database.db;
  final router = Router();

  router.get('/', (Request r) => jsonResponse({
    'name': 'Lanchonete API - Luan e Pedro',
    'version': '1.0.0',
    'status': 'online',
    'documentation': '/docs',
    'health': '/health'
  }));
  router.get('/health', (Request r) => jsonResponse({'status': 'ok'}));
  router.get('/docs', (Request r) => jsonResponse({
    'authentication': 'Use Authorization: Bearer <token> nas rotas protegidas.',
    'roles': ['customer', 'admin'],
    'order_status': _statuses,
    'payment_methods': _payments,
    'order_types': _orderTypes,
    'routes': {
      'POST /auth/register': 'Criar conta de cliente',
      'POST /auth/login': 'Entrar e receber token',
      'GET /me': 'Dados do usuário autenticado',
      'GET /categories': 'Listar categorias',
      'POST /categories': 'Criar categoria (admin)',
      'GET /products': 'Listar produtos; aceita ?category_id=1&available=true',
      'GET /products/<id>': 'Detalhar produto',
      'POST /products': 'Criar produto (admin)',
      'PATCH /products/<id>': 'Editar produto (admin)',
      'DELETE /products/<id>': 'Excluir produto (admin)',
      'POST /orders': 'Criar pedido',
      'GET /orders': 'Listar pedidos do usuário; admin vê todos',
      'GET /orders/<id>': 'Detalhar pedido',
      'PATCH /orders/<id>/status': 'Atualizar status (admin)',
      'PATCH /orders/<id>/payment': 'Atualizar pagamento (admin)',
      'GET /admin/summary': 'Resumo de vendas (admin)'
    },
    'order_example': {
      'customer_name': 'Maria',
      'customer_phone': '49999999999',
      'order_type': 'pickup',
      'payment_method': 'pix',
      'notes': 'Sem cebola',
      'items': [{'product_id': 1, 'quantity': 2, 'notes': 'Sem molho'}]
    }
  }));

  Map<String, Object?>? currentUser(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    final token = header.substring(7).trim();
    if (token.isEmpty) return null;
    final rows = db.select('SELECT u.id, u.name, u.email, u.role FROM users u JOIN sessions s ON s.user_id=u.id WHERE s.token=?', [token]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Response? requireAuth(Request request, {bool admin = false}) {
    final user = currentUser(request);
    if (user == null) return jsonResponse({'error': 'Não autenticado.'}, status: 401);
    if (admin && user['role'] != 'admin') return jsonResponse({'error': 'Acesso restrito ao administrador.'}, status: 403);
    request.context['user'] = user;
    return null;
  }

  router.post('/auth/register', (Request r) {
    final b = bodyMap(r);
    if (b == null) return jsonResponse({'error': 'JSON inválido.'}, status: 400);
    final name = _str(b['name']), email = _str(b['email'])?.toLowerCase(), password = _str(b['password']);
    if (name == null || email == null || password == null || password.length < 8) {
      return jsonResponse({'error': 'Informe nome, e-mail e senha com pelo menos 8 caracteres.'}, status: 422);
    }
    final salt = newSalt();
    try {
      db.execute('INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?,?)',
        [name, email, '${salt}:${hashPassword(password, salt)}', 'customer']);
      final id = db.lastInsertRowId;
      final token = newToken();
      db.execute('INSERT INTO sessions(token,user_id) VALUES(?,?)', [token, id]);
      return jsonResponse({'message': 'Conta criada.', 'token': token,
        'user': {'id': id, 'name': name, 'email': email, 'role': 'customer'}}, status: 201);
    } catch (_) { return jsonResponse({'error': 'Este e-mail já está cadastrado.'}, status: 409); }
  });

  router.post('/auth/login', (Request r) {
    final b = bodyMap(r);
    if (b == null) return jsonResponse({'error': 'JSON inválido.'}, status: 400);
    final email = _str(b['email'])?.toLowerCase(), password = _str(b['password']);
    if (email == null || password == null) return jsonResponse({'error': 'E-mail e senha são obrigatórios.'}, status: 422);
    final rows = db.select('SELECT id,name,email,role,password_hash FROM users WHERE email=?', [email]);
    if (rows.isEmpty) return jsonResponse({'error': 'Credenciais inválidas.'}, status: 401);
    final stored = (rows.first['password_hash'] as String).split(':');
    if (stored.length != 2 || hashPassword(password, stored[0]) != stored[1]) {
      return jsonResponse({'error': 'Credenciais inválidas.'}, status: 401);
    }
    final token = newToken();
    db.execute('INSERT INTO sessions(token,user_id) VALUES(?,?)', [token, rows.first['id']]);
    return jsonResponse({'token': token, 'user': {
      'id': rows.first['id'], 'name': rows.first['name'],
      'email': rows.first['email'], 'role': rows.first['role']
    }});
  });

  router.post('/auth/logout', (Request r) {
    final header = r.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return jsonResponse({'error': 'Não autenticado.'}, status: 401);
    db.execute('DELETE FROM sessions WHERE token=?', [header.substring(7).trim()]);
    return jsonResponse({'message': 'Sessão encerrada.'});
  });

  router.get('/me', (Request r) {
    final auth = requireAuth(r); if (auth != null) return auth;
    return jsonResponse(r.context['user']);
  });

  router.get('/categories', (Request r) {
    final rows = db.select('SELECT * FROM categories WHERE active=1 ORDER BY name');
    return jsonResponse(rows.map((e) => e).toList());
  });
  router.post('/categories', (Request r) {
    final auth = requireAuth(r, admin: true); if (auth != null) return auth;
    final b = bodyMap(r); final name = _str(b?['name']);
    if (name == null) return jsonResponse({'error': 'Nome obrigatório.'}, status: 422);
    try {
      db.execute('INSERT INTO categories(name,description) VALUES(?,?)', [name, _str(b?['description'])]);
      return jsonResponse({'id': db.lastInsertRowId, 'name': name}, status: 201);
    } catch (_) { return jsonResponse({'error': 'Categoria já existe.'}, status: 409); }
  });

  router.get('/products', (Request r) {
    final category = r.url.queryParameters['category_id'];
    final available = r.url.queryParameters['available'];
    var sql = 'SELECT p.*, c.name AS category_name FROM products p LEFT JOIN categories c ON c.id=p.category_id WHERE 1=1';
    final args = <Object?>[];
    if (category != null && int.tryParse(category) != null) { sql += ' AND p.category_id=?'; args.add(int.parse(category)); }
    if (available == 'true') sql += ' AND p.available=1';
    if (available == 'false') sql += ' AND p.available=0';
    sql += ' ORDER BY p.name';
    return jsonResponse(db.select(sql, args).map((e) => e).toList());
  });
  router.get('/products/<id>', (Request r, String id) {
    final rows = db.select('SELECT * FROM products WHERE id=?', [int.tryParse(id) ?? -1]);
    if (rows.isEmpty) return jsonResponse({'error': 'Produto não encontrado.'}, status: 404);
    return jsonResponse(rows.first);
  });
  router.post('/products', (Request r) {
    final auth = requireAuth(r, admin: true); if (auth != null) return auth;
    final b = bodyMap(r); final name = _str(b?['name']); final price = _int(b?['price_cents']);
    if (name == null || price == null || price < 0) return jsonResponse({'error': 'Nome e price_cents válido são obrigatórios.'}, status: 422);
    final category = _int(b?['category_id']);
    db.execute('INSERT INTO products(category_id,name,description,price_cents,image_url,available) VALUES(?,?,?,?,?,?)',
      [category, name, _str(b?['description']), price, _str(b?['image_url']), b?['available'] == false ? 0 : 1]);
    return jsonResponse({'id': db.lastInsertRowId, 'name': name, 'price_cents': price}, status: 201);
  });
  router.patch('/products/<id>', (Request r, String id) {
    final auth = requireAuth(r, admin: true); if (auth != null) return auth;
    final b = bodyMap(r); if (b == null) return jsonResponse({'error': 'JSON inválido.'}, status: 400);
    final productId = int.tryParse(id); if (productId == null) return jsonResponse({'error': 'ID inválido.'}, status: 400);
    final old = db.select('SELECT * FROM products WHERE id=?', [productId]);
    if (old.isEmpty) return jsonResponse({'error': 'Produto não encontrado.'}, status: 404);
    final p = old.first;
    db.execute('UPDATE products SET category_id=?,name=?,description=?,price_cents=?,image_url=?,available=? WHERE id=?',
      [_int(b['category_id']) ?? p['category_id'], _str(b['name']) ?? p['name'],
       b.containsKey('description') ? b['description'] : p['description'],
       _int(b['price_cents']) ?? p['price_cents'],
       b.containsKey('image_url') ? b['image_url'] : p['image_url'],
       b['available'] == null ? p['available'] : (b['available'] == true ? 1 : 0), productId]);
    return jsonResponse({'message': 'Produto atualizado.'});
  });
  router.delete('/products/<id>', (Request r, String id) {
    final auth = requireAuth(r, admin: true); if (auth != null) return auth;
    db.execute('DELETE FROM products WHERE id=?', [int.tryParse(id) ?? -1]);
    return jsonResponse({'message': 'Produto removido.'});
  });

  router.post('/orders', (Request r) {
    final b = bodyMap(r); if (b == null) return jsonResponse({'error': 'JSON inválido.'}, status: 400);
    final name = _str(b['customer_name']);
    final payment = _str(b['payment_method']);
    final type = _str(b['order_type']) ?? 'pickup';
    final items = b['items'];
    if (name == null || payment == null || !_payments.contains(payment) || !_orderTypes.contains(type) || items is! List || items.isEmpty) {
      return jsonResponse({'error': 'Informe customer_name, payment_method, order_type válido e ao menos um item.'}, status: 422);
    }
    if (type == 'delivery' && _str(b['address']) == null) return jsonResponse({'error': 'Endereço obrigatório para entrega.'}, status: 422);
    var subtotal = 0;
    final validated = <Map<String, Object?>>[];
    for (final item in items) {
      if (item is! Map) return jsonResponse({'error': 'Item inválido.'}, status: 422);
      final productId = _int(item['product_id']), qty = _int(item['quantity']);
      if (productId == null || qty == null || qty < 1 || qty > 99) return jsonResponse({'error': 'Produto ou quantidade inválida.'}, status: 422);
      final products = db.select('SELECT id,name,price_cents FROM products WHERE id=? AND available=1', [productId]);
      if (products.isEmpty) return jsonResponse({'error': 'Produto $productId não encontrado ou indisponível.'}, status: 422);
      final product = products.first;
      final line = (product['price_cents'] as int) * qty;
      subtotal += line;
      validated.add({'product_id': productId, 'name': product['name'], 'price': product['price_cents'], 'qty': qty, 'notes': _str(item['notes']), 'line': line});
    }
    final fee = type == 'delivery' ? (_int(b['delivery_fee_cents']) ?? 0) : 0;
    if (fee < 0) return jsonResponse({'error': 'Taxa de entrega inválida.'}, status: 422);
    final total = subtotal + fee;
    db.execute('BEGIN');
    try {
      db.execute('INSERT INTO orders(user_id,customer_name,customer_phone,order_type,address,notes,payment_method,subtotal_cents,delivery_fee_cents,total_cents) VALUES(?,?,?,?,?,?,?,?,?,?)',
        [null, name, _str(b['customer_phone']), type, _str(b['address']), _str(b['notes']), payment, subtotal, fee, total]);
      final orderId = db.lastInsertRowId;
      for (final item in validated) {
        db.execute('INSERT INTO order_items(order_id,product_id,product_name,unit_price_cents,quantity,notes,line_total_cents) VALUES(?,?,?,?,?,?,?)',
          [orderId, item['product_id'], item['name'], item['price'], item['qty'], item['notes'], item['line']]);
      }
      db.execute('COMMIT');
      return jsonResponse({'id': orderId, 'status': 'pending', 'subtotal_cents': subtotal,
        'delivery_fee_cents': fee, 'total_cents': total, 'items': validated}, status: 201);
    } catch (_) {
      db.execute('ROLLBACK');
      return jsonResponse({'error': 'Não foi possível registrar o pedido.'}, status: 500);
    }
  });

  router.get('/orders', (Request r) {
    final auth = requireAuth(r); if (auth != null) return auth;
    final user = r.context['user'] as Map;
    final isAdmin = user['role'] == 'admin';
    final status = r.url.queryParameters['status'];
    var sql = 'SELECT * FROM orders WHERE 1=1'; final args = <Object?>[];
    if (!isAdmin) { sql += ' AND user_id=?'; args.add(user['id']); }
    if (status != null && _statuses.contains(status)) { sql += ' AND status=?'; args.add(status); }
    sql += ' ORDER BY created_at DESC LIMIT 100';
    return jsonResponse(db.select(sql, args).map((e) => e).toList());
  });
  router.get('/orders/<id>', (Request r, String id) {
    final auth = requireAuth(r); if (auth != null) return auth;
    final user = r.context['user'] as Map;
    final rows = db.select('SELECT * FROM orders WHERE id=?', [int.tryParse(id) ?? -1]);
    if (rows.isEmpty) return jsonResponse({'error': 'Pedido não encontrado.'}, status: 404);
    if (user['role'] != 'admin' && rows.first['user_id'] != user['id']) return jsonResponse({'error': 'Acesso negado.'}, status: 403);
    final items = db.select('SELECT * FROM order_items WHERE order_id=?', [int.parse(id)]);
    return jsonResponse({'order': rows.first, 'items': items});
  });
  router.patch('/orders/<id>/status', (Request r, String id) {
    final auth = requireAuth(r, admin: true); if (auth != null) return auth;
    final status = _str(bodyMap(r)?['status']);
    if (status == null || !_statuses.contains(status)) return jsonResponse({'error': 'Status inválido. Valores: ${_statuses.join(', ')}'}, status: 422);
    db.execute('UPDATE orders SET status=?,updated_at=CURRENT_TIMESTAMP WHERE id=?', [status, int.tryParse(id) ?? -1]);
    return jsonResponse({'message': 'Status atualizado.'});
  });
  router.patch('/orders/<id>/payment', (Request r, String id) {
    final auth = requireAuth(r, admin: true); if (auth != null) return auth;
    final status = _str(bodyMap(r)?['payment_status']);
    if (!['pending','paid','refunded','failed'].contains(status)) return jsonResponse({'error': 'payment_status inválido.'}, status: 422);
    db.execute('UPDATE orders SET payment_status=?,updated_at=CURRENT_TIMESTAMP WHERE id=?', [status, int.tryParse(id) ?? -1]);
    return jsonResponse({'message': 'Pagamento atualizado.'});
  });

  router.get('/admin/summary', (Request r) {
    final auth = requireAuth(r, admin: true); if (auth != null) return auth;
    final totals = db.select("SELECT COUNT(*) AS orders_count, COALESCE(SUM(total_cents),0) AS revenue_cents FROM orders WHERE status != 'cancelled'");
    final statuses = db.select('SELECT status,COUNT(*) AS quantity FROM orders GROUP BY status');
    final top = db.select('SELECT product_name,SUM(quantity) AS quantity FROM order_items GROUP BY product_name ORDER BY quantity DESC LIMIT 5');
    return jsonResponse({'orders': totals.first['orders_count'], 'revenue_cents': totals.first['revenue_cents'],
      'by_status': statuses, 'top_products': top});
  });

  return _bodyMiddleware()(router.call);
}
