// packages/next_dart_protocol/lib/src/crypto.dart
import 'package:cryptography/cryptography.dart';

/// Ed25519 signing/verification wrapper.
class NdSigner {
  final Ed25519 _algo = Ed25519();

  Future<List<int>> sign(List<int> message, SimpleKeyPair keyPair) async {
    final sig = await _algo.sign(message, keyPair: keyPair);
    return sig.bytes;
  }

  Future<bool> verify(
      List<int> message, List<int> signatureBytes, SimplePublicKey publicKey) {
    return _algo.verify(message,
        signature: Signature(signatureBytes, publicKey: publicKey));
  }
}

/// Output of an AES-GCM encryption.
class NdSealed {
  final List<int> cipherText;
  final List<int> nonce;
  final List<int> mac;
  const NdSealed(this.cipherText, this.nonce, this.mac);
}

/// AES-256-GCM authenticated encryption wrapper.
class NdCipher {
  final AesGcm _algo = AesGcm.with256bits();

  Future<NdSealed> encrypt(List<int> clear, SecretKey key) async {
    final nonce = _algo.newNonce();
    final box = await _algo.encrypt(clear, secretKey: key, nonce: nonce);
    return NdSealed(box.cipherText, box.nonce, box.mac.bytes);
  }

  Future<List<int>> decrypt(
      List<int> cipherText, List<int> nonce, List<int> mac, SecretKey key) {
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    return _algo.decrypt(box, secretKey: key);
  }
}
