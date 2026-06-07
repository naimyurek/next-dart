// examples/counter_app/server/tool/gen_keys.dart
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

// ⚠ DEMO HELPER — prints fresh keys for the example. The values you paste into
// keys.dart are committed to a PUBLIC repo and are therefore NOT secret. For a
// real app, run this to generate fresh random keys and keep them OUT of version
// control (e.g. an untracked .env or a secrets manager).

/// Run once: `dart run tool/gen_keys.dart`. Paste the printed constants into
/// BOTH server/lib/keys.dart and app/lib/keys.dart so the client can verify and
/// decrypt what the server signs and encrypts.
Future<void> main() async {
  final kp = await Ed25519().newKeyPair();
  final seed = await kp.extractPrivateKeyBytes(); // 32-byte Ed25519 seed
  final pub = await kp.extractPublicKey();
  final rng = Random.secure();
  final secret = List<int>.generate(32, (_) => rng.nextInt(256));
  print("const signingSeedB64 = '${base64.encode(seed)}';");
  print("const signingPublicKeyB64 = '${base64.encode(pub.bytes)}';");
  print("const secretKeyB64 = '${base64.encode(secret)}';");
}
