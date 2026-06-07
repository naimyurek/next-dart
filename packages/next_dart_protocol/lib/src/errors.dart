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
