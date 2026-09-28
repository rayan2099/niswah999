import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/core/models/madhhab_type.dart';

void main() {
  test('strict Madhhab parser accepts only real schools', () {
    expect(MadhhabType.fromValue('hanafi'), MadhhabType.hanafi);
    expect(MadhhabType.fromValue(' MALIKI '), MadhhabType.maliki);
    expect(MadhhabType.tryFromValue('shafii'), MadhhabType.shafii);
    expect(MadhhabType.tryFromValue('hanbali'), MadhhabType.hanbali);
  });

  test('unknown values never default to a real Madhhab', () {
    expect(MadhhabType.tryFromValue(null), isNull);
    expect(MadhhabType.tryFromValue(''), isNull);
    expect(MadhhabType.tryFromValue('unknown'), isNull);
    expect(MadhhabType.tryFromValue('not-a-school'), isNull);
    expect(
      () => MadhhabType.fromValue('not-a-school'),
      throwsA(isA<FormatException>()),
    );
  });
}
