import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:miaoban/core/api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android trusts deployed HTTPS and unauthenticated API stays private',
    (tester) async {
      const url = String.fromEnvironment('API_BASE_URL');
      expect(url, startsWith('https://'));
      final api = Api();
      try {
        final ready = await api.dio.get<Map<String, dynamic>>('/ready');
        expect(ready.statusCode, 200);
        expect(ready.data?['status'], 'ready');
        await expectLater(
          api.get('/auth/me'),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
        );
      } finally {
        api.dio.close(force: true);
      }
    },
  );
}
