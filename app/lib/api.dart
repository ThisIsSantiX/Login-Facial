import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// URL del backend. Cámbiala al compilar:
///   flutter run --dart-define=API_URL=http://192.168.1.50:8000
/// 10.0.2.2 es el localhost del PC visto desde el emulador de Android.
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;

  /// Código HTTP; null si no hubo respuesta (fallo de red).
  final int? status;
  @override
  String toString() => message;
}

class User {
  User(this.username, this.fullName);
  final String username;
  final String fullName;
}

/// Selfie de frente + selfie con la cabeza girada (prueba de vida).
class FacePhotos {
  FacePhotos(this.front, this.turned);
  final Uint8List front;
  final Uint8List turned;
}

class ConsentInfo {
  const ConsentInfo({
    required this.termsAccepted,
    required this.termsVersion,
    required this.aiImprovementOptIn,
    required this.consentAt,
  });

  final bool termsAccepted;
  final String termsVersion;
  final bool aiImprovementOptIn;
  final DateTime consentAt;

  Map<String, String> toFields() => {
    'terms_accepted': termsAccepted.toString(),
    'terms_version': termsVersion,
    'ai_improvement_opt_in': aiImprovementOptIn.toString(),
    'consent_at': consentAt.toUtc().toIso8601String(),
  };
}

class Api {
  static const _tokenKey = 'token';
  static const _consentKey = 'consent_v1';
  static const _timeout = Duration(seconds: 25);

  static Future<Map<String, dynamic>> _send(http.BaseRequest req) async {
    try {
      final res = await http.Response.fromStream(
        await req.send().timeout(_timeout),
      );
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode >= 400) {
        throw ApiException(
          body['detail']?.toString() ?? 'Error ${res.statusCode}',
          res.statusCode,
        );
      }
      return body as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('No hay conexión con el servidor.');
    }
  }

  static http.MultipartRequest _multipart(
    String path,
    Map<String, String> fields,
    FacePhotos photos,
  ) {
    return http.MultipartRequest('POST', Uri.parse('$apiUrl$path'))
      ..fields.addAll(fields)
      ..files.addAll([
        http.MultipartFile.fromBytes(
          'photo',
          photos.front,
          filename: 'front.jpg',
        ),
        http.MultipartFile.fromBytes(
          'photo_turn',
          photos.turned,
          filename: 'turn.jpg',
        ),
      ]);
  }

  static Future<void> register(
    String username,
    String pin,
    FacePhotos photos,
    ConsentInfo consent,
  ) async {
    final fields = <String, String>{'username': username, 'pin': pin}
      ..addAll(consent.toFields());
    await _send(_multipart('/register', fields, photos));
    await saveConsent(consent);
  }

  static Future<void> saveConsent(ConsentInfo consent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_consentKey, jsonEncode(consent.toFields()));
  }

  static Future<ConsentInfo?> loadConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_consentKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return ConsentInfo(
        termsAccepted: data['terms_accepted'] == 'true',
        termsVersion: data['terms_version'] as String,
        aiImprovementOptIn: data['ai_improvement_opt_in'] == 'true',
        consentAt: DateTime.parse(data['consent_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateAiConsent(bool enabled) async {
    final existing = await loadConsent();
    if (existing == null) return;
    final updated = ConsentInfo(
      termsAccepted: existing.termsAccepted,
      termsVersion: existing.termsVersion,
      aiImprovementOptIn: enabled,
      consentAt: DateTime.now().toUtc(),
    );
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null) {
      await _send(
        http.Request('POST', Uri.parse('$apiUrl/consent'))
          ..headers['Authorization'] = 'Bearer $token'
          ..bodyFields = {
            'ai_improvement_opt_in': enabled.toString(),
            'terms_version': updated.termsVersion,
          },
      );
    }
    await saveConsent(updated);
  }

  static Future<User> login(String username, FacePhotos photos) async {
    final data = await _send(
      _multipart('/login', {'username': username}, photos),
    );
    return _openSession(data);
  }

  /// Entra con usuario y PIN, sin escáner facial.
  static Future<User> loginPin(String username, String pin) async {
    final data = await _send(
      http.Request('POST', Uri.parse('$apiUrl/login_pin'))
        ..bodyFields = {'username': username, 'pin': pin},
    );
    return _openSession(data);
  }

  /// Reconoce al usuario por el rostro, sin escribir el nombre.
  static Future<User> identify(FacePhotos photos) async {
    final data = await _send(_multipart('/identify', {}, photos));
    return _openSession(data);
  }

  static Future<User> _openSession(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, data['token']);
    return User(data['username'], data['full_name']);
  }

  /// Devuelve el usuario si hay una sesión guardada y sigue vigente.
  static Future<User?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null) return null;
    try {
      final data = await _send(
        http.Request('GET', Uri.parse('$apiUrl/me'))
          ..headers['Authorization'] = 'Bearer $token',
      );
      return User(data['username'], data['full_name']);
    } on ApiException {
      return null;
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    await prefs.remove(_tokenKey);
    if (token == null) return;
    try {
      await _send(
        http.Request('POST', Uri.parse('$apiUrl/logout'))
          ..headers['Authorization'] = 'Bearer $token',
      );
    } on ApiException {
      // La sesión local ya se borró; si el servidor no responde no importa.
    }
  }
}
