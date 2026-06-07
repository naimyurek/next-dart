/// The wire/protocol version this build speaks.
const String kProtocolVersion = '1.0.0';

/// Returns true if semver string [a] is strictly less than [b].
/// Accepts simple "x.y.z" forms (no pre-release handling in MVP).
bool semverLt(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i];
  }
  return false;
}
