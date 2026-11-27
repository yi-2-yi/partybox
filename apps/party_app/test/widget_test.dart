import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/core/audio/narrator_service.dart';
import 'package:party_app/core/state/app_controller.dart';
import 'package:party_app/core/transport/lan_host_transport_io.dart';
import 'package:party_app/core/transport/websocket_transport.dart';
import 'package:party_app/main.dart';
import 'package:party_core/party_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('Home -> 12-player Demo Lobby (Sheriff ON) -> RolePeek -> Confirm', (tester) async {
    final ctrl = AppController(narrator: NarratorService(enabled: false));
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(PartyBoxApp(controller: ctrl));
    await tester.pumpAndSettle();

    expect(find.text('PartyBox'), findsOneWidget);
    expect(find.text('掼蛋 · 聚会无线牌局'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('一夜终极狼人 · 换牌推理'), 250);
    expect(find.text('狼人杀 · 智能聚会法官'), findsOneWidget);
    expect(find.text('一夜终极狼人 · 换牌推理'), findsOneWidget);

    // Start 12-player demo with sheriff enabled by default
    await ctrl.startLocalDemo(preset: WerewolfConfig.preset12Idiot());
    await tester.pumpAndSettle();

    expect(find.textContaining('狼人杀大厅'), findsOneWidget);
    expect(find.textContaining('已入座玩家（12 / 12）'), findsOneWidget);
    expect(find.textContaining('开始发牌（12人 · 含警长）'), findsOneWidget);

    // Start game -> WerewolfTablePage with hidden anti-peek role card
    await tester.tap(find.textContaining('开始发牌'));
    await tester.pumpAndSettle();

    expect(find.textContaining('身份牌（已隐藏）'), findsOneWidget);

    // Hold gesture reveals role card, release hides it again
    final cardFinder = find.textContaining('身份牌（已隐藏）');
    final gesture = await tester.startGesture(tester.getCenter(cardFinder));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('阵营'), findsOneWidget);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('身份牌（已隐藏）'), findsOneWidget);

    // Confirm role and advance timers deterministically
    await tester.tap(find.text('我已记住身份，准备天黑'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    // Bots also confirmed -> entered Night 1!
    expect(ctrl.snapshot!.gameState!['dayNumber'], 1);
    expect(ctrl.snapshot!.gameState!['isNight'], isTrue);

    await tester.runAsync(() async {
      await ctrl.leaveRoom();
    });
    await tester.pump();
  });

  test('Embedded LanHostGameTransport serves zero-install iPhone web client over HTTP and syncs WebSocket clients', () async {
    final html = await File('assets/web_client/index.html').readAsString();
    final host = await LanHostGameTransport.start(
      hostName: '房主手机',
      gameType: GameType.werewolf,
      port: 0,
      webClientHtml: html,
    );
    addTearDown(host.close);

    final wsUrl = host.endpointInfo.lanWsUrl!;
    final webUrl = host.endpointInfo.lanWebUrl!;
    expect(wsUrl, startsWith('ws://'));
    expect(webUrl, startsWith('http://'));

    // 1. Verify iPhone Safari GET http://127.0.0.1:<port>/ returns the zero-install HTML client
    await HttpOverrides.runWithHttpOverrides(() async {
      final httpUri = Uri.parse(webUrl).replace(host: '127.0.0.1');
      final httpClient = HttpClient();
      try {
        final req = await httpClient.getUrl(httpUri);
        final resp = await req.close();
        expect(resp.statusCode, HttpStatus.ok);
        expect(resp.headers.contentType?.mimeType, 'text/html');
        final body = await resp.transform(utf8.decoder).join();
        expect(body, contains('PartyBox'));
        expect(body, contains('join_room'));
      } finally {
        httpClient.close(force: true);
      }
    }, _RealHttpOverrides());

    // 2. Connect a real LAN WebSocket client to the same host port
    final uri = Uri.parse(wsUrl).replace(host: '127.0.0.1').toString();
    final client = WebSocketGameTransport(
      wsUrl: uri,
      mode: ConnectionMode.lanClient,
      initialMessage: const ClientMessage(
        type: ClientMessageType.joinRoom,
        payload: {'name': '朋友手机', 'avatarIndex': 4},
      ),
    );
    addTearDown(client.close);

    final clientSnapFuture = client.snapshots.firstWhere(
      (s) => s.players.length == 2,
    );
    await client.connect();
    final snap = await clientSnapFuture.timeout(const Duration(seconds: 5));
    expect(snap.players.map((p) => p.name), containsAll(['房主手机', '朋友手机']));
  });

  testWidgets('Guandan Demo Lobby -> Deal 27 cards -> Hint & Play flow', (tester) async {
    final ctrl = AppController(narrator: NarratorService(enabled: false));
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(PartyBoxApp(controller: ctrl));
    await tester.pumpAndSettle();

    await ctrl.startGuandanDemo(config: const GuandanConfig(startLevel: 2));
    await tester.pumpAndSettle();

    expect(find.textContaining('掼蛋大厅'), findsOneWidget);
    expect(find.textContaining('已入座玩家（4 / 4）'), findsOneWidget);
    expect(find.textContaining('开始发牌（4人掼蛋 · 打 2 起）'), findsOneWidget);

    await tester.tap(find.textContaining('开始发牌'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('掼蛋 · 第 1 局 · 打 2'), findsOneWidget);
    expect((ctrl.snapshot!.gameState!['myHand'] as List).length, 27);

    // Let AI bots take turns until it becomes human's turn
    for (var i = 0; i < 6; i++) {
      if (ctrl.snapshot!.gameState!['isMyTurn'] == true) break;
      await tester.pump(const Duration(milliseconds: 800));
    }

    if (ctrl.snapshot!.gameState!['isMyTurn'] == true) {
      await tester.tap(find.text('提示'));
      await tester.pump();
      await tester.tap(find.text('出牌'));
      await tester.pump();
      expect((ctrl.snapshot!.gameState!['myHand'] as List).length, lessThan(27));
    }

    await tester.runAsync(() async {
      await ctrl.leaveRoom();
    });
    await tester.pump();
  });

  testWidgets('One Night Demo Lobby -> Deal 5+3 -> Anti-peek Role -> NightStep', (tester) async {
    final ctrl = AppController(narrator: NarratorService(enabled: false));
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(PartyBoxApp(controller: ctrl));
    await tester.pumpAndSettle();

    await ctrl.startOneNightDemo(preset: OneNightConfig.preset5());
    await tester.pumpAndSettle();

    expect(find.textContaining('一夜终极狼人大厅'), findsOneWidget);
    expect(find.textContaining('已入座玩家（5 / 5）'), findsOneWidget);
    expect(find.textContaining('开始发牌（5人一夜狼 · 8张牌）'), findsOneWidget);

    await tester.tap(find.textContaining('开始发牌'));
    await tester.pumpAndSettle();

    expect(find.textContaining('一夜狼身份牌（已隐藏）'), findsOneWidget);
    expect(find.text('底牌 A'), findsOneWidget);
    expect(find.text('底牌 B'), findsOneWidget);
    expect(find.text('底牌 C'), findsOneWidget);

    await tester.tap(find.text('我已记住初始身份，准备天黑'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    expect(ctrl.snapshot!.gameState!['phase'], isNot('roleReveal'));

    await tester.runAsync(() async {
      await ctrl.leaveRoom();
    });
    await tester.pump();
  });

  testWidgets('Werewolf polish: avatar picker, custom voice settings & public vote history toggle', (tester) async {
    final ctrl = AppController(narrator: NarratorService(enabled: false));
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(PartyBoxApp(controller: ctrl));
    await tester.pumpAndSettle();

    // 1. Open avatar & nickname dialog and pick an anime avatar (神秘魔法师 index 8)
    await tester.tap(find.text('玩家小明'));
    await tester.pumpAndSettle();
    expect(find.text('小动物系列'), findsOneWidget);
    expect(find.text('动漫人物系列'), findsOneWidget);
    await tester.tap(find.text('神秘魔法师'));
    await tester.pump();
    await tester.tap(find.text('保存头像与昵称'));
    await tester.pumpAndSettle();
    expect(ctrl.avatarIndex, 8);

    // 2. Custom voice settings update & script resolution
    await ctrl.updateVoiceSettings(
      ctrl.voiceSettings.copyWith(
        stylePreset: 'mystery',
        speechRate: 0.42,
        pitch: 0.82,
        customScripts: {'night_wolf': '黑夜降临，狼人开始狩猎。'},
      ),
    );
    expect(
      ctrl.narrator.resolveScriptForEvent(
        const GameEvent(
          id: 'e1',
          type: 'phase_change',
          message: 'test',
          narrationText: '默认台词',
          payload: {'scriptKey': 'night_wolf'},
        ),
      ),
      '黑夜降临，狼人开始狩猎。',
    );

    // 3. Werewolf Lobby shows "记录并公开票型" toggle, and in-game AppBar shows "票型" sheet
    await ctrl.startLocalDemo(
      preset: WerewolfConfig.preset6().copyWith(recordVoteHistory: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('记录并公开票型'), findsOneWidget);

    await tester.tap(find.textContaining('开始发牌'));
    await tester.pumpAndSettle();

    expect(find.text('票型'), findsOneWidget);
    await tester.tap(find.text('票型'));
    await tester.pumpAndSettle();
    expect(find.text('全场公开票型记录'), findsOneWidget);

    await tester.runAsync(() async {
      await ctrl.leaveRoom();
    });
    await tester.pump();
  });
}

class _RealHttpOverrides extends HttpOverrides {}

