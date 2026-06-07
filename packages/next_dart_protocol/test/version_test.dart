import 'package:next_dart_protocol/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('kProtocolVersion is set', () {
    expect(kProtocolVersion, '1.0.0');
  });

  test('semverLt compares correctly', () {
    expect(semverLt('1.0.0', '1.0.1'), isTrue);
    expect(semverLt('1.2.0', '1.10.0'), isTrue);
    expect(semverLt('2.0.0', '1.9.9'), isFalse);
    expect(semverLt('1.0.0', '1.0.0'), isFalse);
  });
}
