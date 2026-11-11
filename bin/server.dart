import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:lanchonete_api/src/app.dart';
import 'package:lanchonete_api/src/database.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final dbPath = Platform.environment['DATABASE_PATH'] ?? 'lanchonete.db';
  final database = AppDatabase(dbPath);
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(createApp(database));

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('API Luan e Pedro rodando em http://${server.address.host}:${server.port}');
  print('Banco SQLite: $dbPath');
}
