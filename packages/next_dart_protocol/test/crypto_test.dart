import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/src/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('sign then verify succeeds; tamper fails', () async {
    final signer = NdSigner();
    final kp = await Ed25519().newKeyPair();
    final pub = await kp.extractPublicKey();
    final msg = [1, 2, 3, 4];
    final sig = await signer.sign(msg, kp);
    expect(await signer.verify(msg, sig, pub), isTrue);
    expect(await signer.verify([9, 9, 9, 9], sig, pub), isFalse);
  });

  test('encrypt then decrypt round-trips', () async {
    final cipher = NdCipher();
    final key = SecretKey(List.filled(32, 7));
    final clear = [10, 20, 30];
    final box = await cipher.encrypt(clear, key);
    final back = await cipher.decrypt(box.cipherText, box.nonce, box.mac, key);
    expect(back, clear);
  });

  test('decrypt with wrong key throws', () async {
    final cipher = NdCipher();
    final box = await cipher.encrypt([1, 2, 3], SecretKey(List.filled(32, 1)));
    expect(
      () => cipher.decrypt(box.cipherText, box.nonce, box.mac, SecretKey(List.filled(32, 2))),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
