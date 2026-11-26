import 'package:Badya/services/adk_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdkService normalizeId', () {
    final adkService = AdkService();

    test('should lowercase strings', () {
      expect(adkService.normalizeId('HELLO'), startsWith('hello-'));
    });

    test('should replace special characters with hyphens and compress consecutive ones', () {
      expect(adkService.normalizeId('hello___world!!!'), startsWith('hello-world-'));
    });

    test('should strip leading and trailing hyphens', () {
      expect(adkService.normalizeId('__hello-world__'), startsWith('hello-world-'));
    });

    test('should handle Arabic characters by replacing them and compressing hyphens', () {
      expect(adkService.normalizeId('main_العربية_weaver'), startsWith('main-weaver-'));
    });

    test('should prepend s- if the result starts with a digit', () {
      expect(adkService.normalizeId('123-hello'), startsWith('s-123-hello-'));
    });

    test('should handle empty or only-special-character strings gracefully with fallback', () {
      expect(adkService.normalizeId('!!!'), startsWith('session-'));
      expect(adkService.normalizeId(''), startsWith('session-'));
    });

    test('should truncate to 63 characters and strip trailing hyphens', () {
      final longString = 'a' * 100;
      final result = adkService.normalizeId(longString);
      expect(result.length <= 63, true);
      
      final longStringWithHyphens = 'a' * 62 + '-b';
      final resultHyphen = adkService.normalizeId(longStringWithHyphens);
      expect(resultHyphen.length <= 63, true);
      expect(resultHyphen.endsWith('-'), false);
    });
  });
}
