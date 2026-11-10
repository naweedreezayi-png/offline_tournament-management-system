import 'package:flutter_test/flutter_test.dart';
import 'package:tournament_master_offline/data/api_client.dart';

void main() {
  group('ApiClient.normalizeUrl', () {
    test('adds http and removes path and trailing slash', () {
      expect(ApiClient.normalizeUrl('192.168.1.5:8080/'), 'http://192.168.1.5:8080');
      expect(ApiClient.normalizeUrl(' https://example.com/api '), 'https://example.com');
    });
    test('rejects empty and unsupported schemes', () {
      expect(ApiClient.normalizeUrl(''), isNull);
      expect(ApiClient.normalizeUrl('ftp://host'), isNull);
    });
  });
}
