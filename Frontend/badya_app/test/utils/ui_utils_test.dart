import 'package:Badya/utils/ui_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UiUtils.isValidEmail', () {
    test('accepts common valid emails', () {
      expect(UiUtils.isValidEmail('user@example.com'), isTrue);
      expect(UiUtils.isValidEmail('first.last@sub.domain.co'), isTrue);
      expect(UiUtils.isValidEmail('user+tag@example.com'), isTrue);
      expect(UiUtils.isValidEmail('  user@example.com  '), isTrue);
    });

    test('rejects empty or whitespace-only input', () {
      expect(UiUtils.isValidEmail(''), isFalse);
      expect(UiUtils.isValidEmail('   '), isFalse);
    });

    test('rejects malformed emails', () {
      expect(UiUtils.isValidEmail('not-an-email'), isFalse);
      expect(UiUtils.isValidEmail('missing@domain'), isFalse);
      expect(UiUtils.isValidEmail('@nodomain.com'), isFalse);
      expect(UiUtils.isValidEmail('no-tld@example.'), isFalse);
      expect(UiUtils.isValidEmail('has space@example.com'), isFalse);
    });
  });
}
