import 'dart:convert';
import 'package:lanchonete_api/src/app.dart';
import 'package:lanchonete_api/src/database.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase database;
  late Handler handler;

  setUp(() {
    database = AppDatabase(':memory:');
    handler = createApp(database);
  });

  tearDown(() => database.close());

  test('health endpoint returns ok', () async {
    final response = await handler(Request('GET', Uri.parse('http://localhost/health')));
    expect(response.statusCode, 200);
    final data = jsonDecode(await response.readAsString());
    expect(data['status'], 'ok');
  });

  test('register creates a customer and returns token', () async {
    final response = await handler(Request('POST', Uri.parse('http://localhost/auth/register'),
      body: jsonEncode({'name':'Teste','email':'teste@email.com','password':'senha1234'})));
    expect(response.statusCode, 201);
    final data = jsonDecode(await response.readAsString());
    expect(data['token'], isNotEmpty);
    expect(data['user']['role'], 'customer');
  });
}
