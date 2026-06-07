/// The wire/protocol version this build speaks.
const String kProtocolVersion = '1.0.0';

/// Returns true if semver string [a] is strictly less than [b].
/// Accepts simple "x.y.z" forms (no pre-release handling in MVP).
/// Throws [FormatException] if either argument does not consist of exactly
/// 3 non-negative integer segments.
bool semverLt(String a, String b) {
  List<int> _parse(String v) {
    final parts = v.split('.');
    if (parts.length != 3) {
      throw FormatException(
          'semverLt: expected exactly 3 dot-separated segments, got "$v"');
    }
    return parts.map((s) {
      final n = int.tryParse(s);
      if (n == null || n < 0) {
        throw FormatException(
            'semverLt: non-integer segment "$s" in version "$v"');
      }
      return n;
    }).toList();
  }

  final pa = _parse(a);
  final pb = _parse(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i];
  }
  return false;
}
