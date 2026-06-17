// packages/next_dart_protocol/lib/src/errors.dart

/// Thrown when an envelope's signature does not verify against the pinned key.
class SignatureError implements Exception {
  @override
  String toString() => 'SignatureError: envelope signature is invalid';
}

/// Thrown when the client is older than the server's required minClientVersion.
class UpdateRequiredError implements Exception {
  final String minClientVersion;
  UpdateRequiredError(this.minClientVersion);
  @override
  String toString() =>
      'UpdateRequiredError: client must be >= $minClientVersion';
}

/// Thrown when wire bytes cannot be parsed into an envelope.
class DecodeError implements Exception {
  final String message;
  DecodeError(this.message);
  @override
  String toString() => 'DecodeError: $message';
}

/// Thrown when an authenticated ECDH handshake response fails verification:
/// the server's Ed25519 signature over `(pubS ‖ pubC ‖ keyId ‖ expiresAt)` does
/// not validate against the PINNED server identity key, or the response is
/// otherwise malformed. A failure here means the handshake may have been
/// tampered with (e.g. a MITM swapped the server's ephemeral X25519 key) and
/// the derived session key MUST NOT be trusted.
class HandshakeError implements Exception {
  final String message;
  HandshakeError(this.message);
  @override
  String toString() => 'HandshakeError: $message';
}
