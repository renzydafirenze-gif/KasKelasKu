import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void mockSecureStorage() {
  final values = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
    final args = call.arguments as Map<dynamic, dynamic>? ?? {};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        return values[key];
      case 'readAll':
        return Map<String, String>.from(values);
      case 'write':
        values[key!] = args['value'] as String;
        return null;
      case 'delete':
        values.remove(key);
        return null;
      case 'deleteAll':
        values.clear();
        return null;
      case 'containsKey':
        return values.containsKey(key);
      default:
        throw MissingPluginException(call.method);
    }
  });
}
