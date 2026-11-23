import 'package:sqlite3/sqlite3.dart';

class AppDatabase {
  late final Database db;

  AppDatabase(String path) {
    db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'customer',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        token TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER,
        name TEXT NOT NULL,
        description TEXT,
        price_cents INTEGER NOT NULL CHECK(price_cents >= 0),
        image_url TEXT,
        available INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(category_id) REFERENCES categories(id)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        order_type TEXT NOT NULL DEFAULT 'pickup',
        address TEXT,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        payment_method TEXT NOT NULL,
        payment_status TEXT NOT NULL DEFAULT 'pending',
        subtotal_cents INTEGER NOT NULL,
        delivery_fee_cents INTEGER NOT NULL DEFAULT 0,
        total_cents INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        unit_price_cents INTEGER NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        notes TEXT,
        line_total_cents INTEGER NOT NULL,
        FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at)');
    _seedMenu();
  }

  void _seedMenu() {
    db.execute('INSERT OR IGNORE INTO categories(name,description) VALUES(?,?)', ['Lanches', 'Hambúrgueres e sanduíches']);
    db.execute('INSERT OR IGNORE INTO categories(name,description) VALUES(?,?)', ['Acompanhamentos', 'Porções para acompanhar']);
    db.execute('INSERT OR IGNORE INTO categories(name,description) VALUES(?,?)', ['Bebidas', 'Bebidas geladas']);
    db.execute('INSERT OR IGNORE INTO categories(name,description) VALUES(?,?)', ['Sobremesas', 'Doces para finalizar o pedido']);
    final categories = <String, int>{};
    for (final row in db.select('SELECT id,name FROM categories')) {
      categories[row['name'] as String] = row['id'] as int;
    }

    final products = [
      [categories['Lanches'], 'X-Burger', 'Pão macio, hambúrguer grelhado, queijo derretido e molho especial da casa.', 2590,
        'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=900&q=85'],
      [categories['Lanches'], 'X-Bacon', 'Hambúrguer grelhado com queijo, bacon crocante, alface e molho especial no pão brioche.', 3290,
        'https://images.unsplash.com/photo-1550547660-d9450f859349?auto=format&fit=crop&w=900&q=85'],
      [categories['Acompanhamentos'], 'Batata frita', 'Batatas douradas e crocantes, servidas quentinhas com sal.', 1490,
        'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?auto=format&fit=crop&w=900&q=85'],
      [categories['Bebidas'], 'Refrigerante lata', 'Refrigerante gelado em lata de 350 ml.', 600,
        'https://images.unsplash.com/photo-1629203851122-3726ecdf080e?auto=format&fit=crop&w=900&q=85'],
      [categories['Bebidas'], 'Água mineral', 'Água mineral sem gás, servida em garrafa de 500 ml.', 400,
        'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?auto=format&fit=crop&w=900&q=85'],
      [categories['Lanches'], 'Cheeseburger duplo', 'Dois hambúrgueres grelhados, queijo cheddar, picles e molho da casa.', 3690,
        'https://images.unsplash.com/photo-1553979459-d2229ba7433a?auto=format&fit=crop&w=900&q=85'],
      [categories['Lanches'], 'Chicken Burger', 'Filé de frango empanado e crocante, alface, tomate e maionese temperada.', 2990,
        'https://images.unsplash.com/photo-1606755962773-d324e0a13086?auto=format&fit=crop&w=900&q=85'],
      [categories['Acompanhamentos'], 'Anéis de cebola', 'Anéis de cebola empanados e crocantes, acompanhados de molho.', 1690,
        'https://images.unsplash.com/photo-1639024471283-03518883512d?auto=format&fit=crop&w=900&q=85'],
      [categories['Acompanhamentos'], 'Nuggets de frango', 'Porção com 8 nuggets de frango empanados, acompanhada de molho.', 1890,
        'https://images.unsplash.com/photo-1562967960-fafc1f7c8e4f?auto=format&fit=crop&w=900&q=85'],
      [categories['Bebidas'], 'Suco de laranja', 'Suco de laranja gelado, preparado para acompanhar seu lanche.', 900,
        'https://images.unsplash.com/photo-1613478223719-2ab802602423?auto=format&fit=crop&w=900&q=85'],
      [categories['Sobremesas'], 'Brownie com sorvete', 'Brownie de chocolate servido com uma bola de sorvete de creme.', 1990,
        'https://images.unsplash.com/photo-1563805042-7684c019e1cb?auto=format&fit=crop&w=900&q=85'],
    ];
    for (final product in products) {
      final existing = db.select('SELECT id FROM products WHERE name=? ORDER BY id LIMIT 1', [product[1]]);
      if (existing.isEmpty) {
        db.execute('INSERT INTO products(category_id,name,description,price_cents,image_url) VALUES(?,?,?,?,?)', product);
      } else {
        db.execute('UPDATE products SET description=COALESCE(description,?),image_url=COALESCE(image_url,?) WHERE id=?',
          [product[2], product[4], existing.first['id']]);
      }
    }
  }

  void close() => db.dispose();
}
