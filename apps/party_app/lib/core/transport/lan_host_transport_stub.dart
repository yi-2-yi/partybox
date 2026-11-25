import 'package:party_core/party_core.dart';

import 'game_transport.dart';

Future<GameTransport> createLanHostTransport({
  required String hostName,
  required GameType gameType,
  int hostAvatarIndex = 0,
  int port = 8765,
}) {
  throw UnsupportedError(
    '浏览器网页版暂不支持作为局域网主机建房，请在 Android / iOS / Windows 客户端中使用局域网/热点建房，或选择联网模式 / 单人体验。',
  );
}
