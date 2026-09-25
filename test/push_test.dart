import 'dart:async';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:ai_dashboard/data/push/push_messaging.dart';
import 'package:ai_dashboard/providers/push_provider.dart';
import 'package:ai_dashboard/providers/settings_provider.dart';
import 'package:ai_dashboard_server/api.dart';
import 'package:ai_dashboard_server/push/push_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const token = 'test-token-0123456789abcdef';

class FakeMessaging implements PushMessaging {
  @override
  Future<bool> init() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String?> getToken() async => 'fcm-token';

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<IncomingPush> get onForeground => const Stream.empty();

  @override
  Stream<IncomingPush> get onOpened => const Stream.empty();

  @override
  Future<IncomingPush?> initialOpened() async => null;
}

void main() {
  test('the phone registers its events with the PC and leaves when they are '
      'all off', () async {
    final mock = MockAgentBackend(simulate: false, latency: Duration.zero);
    final dataDir = await Directory.systemTemp.createTemp('push');
    final notifier = PushNotifier(mock, dataDir: dataDir.path);
    final server = await shelf_io.serve(
      buildHandler(mock, token: token, push: notifier),
      '127.0.0.1',
      0,
    );
    final container = ProviderContainer(
      overrides: [pushMessagingProvider.overrideWithValue(FakeMessaging())],
    );
    addTearDown(() async {
      container.dispose();
      await server.close(force: true);
      notifier.dispose();
      mock.dispose();
      await dataDir.delete(recursive: true);
    });

    Future<void> until(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) fail('Timed out');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    container.listen(pushProvider, (_, _) {});
    expect(container.read(pushProvider).status, PushStatus.demo);

    container.read(settingsProvider.notifier)
      ..setServerUrl('http://127.0.0.1:${server.port}')
      ..setAuthToken(token)
      ..setConnectionMode(ConnectionMode.server);
    await until(
      () => container.read(pushProvider).status == PushStatus.pcCantSend,
    );
    expect(notifier.devices.single.token, 'fcm-token');
    expect(notifier.devices.single.events, {
      PushEvent.failed,
      PushEvent.replied,
    });

    container.read(settingsProvider.notifier)
      ..setNotify(PushEvent.failed, false)
      ..setNotify(PushEvent.replied, false);
    await until(() => notifier.devices.isEmpty);
    expect(container.read(pushProvider).status, PushStatus.off);
  });

  test('tapping a notification opens what it is about', () {
    expect(
      PushController.routeFor({'agentId': 'a1', 'chatId': 'c1'}),
      '/agent/a1?chat=c1',
    );
    expect(
      PushController.routeFor({'projectId': 'p1', 'agentId': 'a1'}),
      '/project/p1',
    );
    expect(PushController.routeFor({'agentId': 'a1'}), '/agent/a1');
    expect(PushController.routeFor({}), isNull);
  });
}
