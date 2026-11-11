import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

String newToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

// Hash simples para ambiente acadêmico. Em produção, substitua por Argon2id/bcrypt
// e implemente limitação de tentativas, HTTPS e política de senhas.
String hashPassword(String password, String salt) =>
    sha256.convert(utf8.encode('$salt:$password')).toString();

String newSalt() {
  final random = Random.secure();
  return List<int>.generate(16, (_) => random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
