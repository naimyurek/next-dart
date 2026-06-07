// packages/next_dart_client/lib/src/client.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'source.dart';

/// Talks to a next-dart backend: fetches pages and dispatches actions, verifying
/// each envelope's signature and decrypting its payload.
class NextDartClient implements NextDartSource {
  final Uri baseUrl;
  final SimplePublicKey signingPublicKey;
  final SecretKey secretKey;
  final String clientVersion;
  final http.Client _http;

  NextDartClient({
    required this.baseUrl,
    required this.signingPublicKey,
    required this.secretKey,
    this.clientVersion = '1.0.0',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  @override
  Future<EnvelopeContent> fetchPage(String route) async {
    final res = await _http.get(
        baseUrl.replace(path: '/__page', queryParameters: {'route': route}));
    return _decode(res);
  }

  @override
  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args,
      {required String route}) async {
    final res = await _http.post(
      baseUrl.replace(path: '/__action'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'action': action, 'args': args, 'route': route}),
    );
    return _decode(res);
  }

  Future<EnvelopeContent> _decode(http.Response res) {
    if (res.statusCode != 200) {
      throw DecodeError('server returned ${res.statusCode}: ${res.body}');
    }
    return decodeEnvelope(
      res.bodyBytes,
      secretKey: secretKey,
      signingPublicKey: signingPublicKey,
      clientVersion: clientVersion,
    );
  }

  void close() => _http.close();
}
