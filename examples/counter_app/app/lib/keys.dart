// examples/counter_app/app/lib/keys.dart — identical values to server/lib/keys.dart
// The public key and shared secret let the client verify signatures and decrypt payloads.

// ════════════════════════════════════════════════════════════════════
// DEMO KEYS — NOT FOR PRODUCTION USE.
// These values are committed to a public repository, so anyone can read
// them. They exist only so the example runs out of the box. Before
// deploying anything real, run `dart run tool/gen_keys.dart` to generate
// fresh random keys and keep secrets out of version control.
// ════════════════════════════════════════════════════════════════════
const signingPublicKeyB64 = 'DQgjF99pkNXN/Xnym4R+xLOiAxPjsRG7NbJnkTVe1xQ=';
const secretKeyB64 = 'DRQbIikwNz5FTFNaYWhvdn2Ei5KZoKeutbzDytHY3+Y=';
