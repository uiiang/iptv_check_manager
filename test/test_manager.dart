import 'package:iptv_check_manager/iptv_check_manager.dart';
import 'package:test/test.dart';

void main() {
  group("Simple tests", () {
    final manager = CheckManager.instance;

    setUp(() async {
      await manager.init(isolates: 2);
      await Future.delayed(const Duration(seconds: 1));
    });

    tearDown(() async {
      await manager.dispose();
    });

    test("Initialized", () {
      expect(manager.initialized, isTrue);
    });

    test("Disposed", () async {
      await manager.dispose();
      expect(manager.queue, isEmpty);
      expect(manager.initialized, isFalse);
    });
  });

  // To be continued..
}
