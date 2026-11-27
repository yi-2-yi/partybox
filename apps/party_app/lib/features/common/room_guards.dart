import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:party_core/party_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/party_theme.dart';

/// Prompts for confirmation before exiting a live room so the LAN Host or an
/// active player never accidentally dissolves or leaves a game in progress.
Future<void> confirmLeaveRoom(
  BuildContext context,
  AppController controller,
) async {
  final endpoint = controller.endpointInfo;
  final snap = controller.snapshot;

  if (endpoint?.mode == ConnectionMode.localDemo || snap == null) {
    await controller.leaveRoom();
    return;
  }

  final isLanHost = endpoint?.mode == ConnectionMode.lanHost;
  final isPlaying = snap.status == RoomStatus.playing;

  if (!isLanHost && !isPlaying) {
    await controller.leaveRoom();
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: PartyColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(
            isLanHost ? Icons.warning_amber_rounded : Icons.exit_to_app,
            color: isLanHost ? PartyColors.wolfRed : PartyColors.gold,
          ),
          const SizedBox(width: 8),
          Text(
            isLanHost ? '确认解散局域网房间？' : '确认暂时退出对局？',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ],
      ),
      content: Text(
        isLanHost
            ? '你是当前局域网/热点房主，退出房间将立即关闭主机并中断所有人的对局。\n\n如需让掉线朋友重新加入，点右上角「二维码」让他们重扫即可。'
            : '游戏正在进行中。退出后你的座位与手牌仍会保留，重新扫码或重连即可无缝回到原座位。',
        style: const TextStyle(
          color: PartyColors.textSecondary,
          height: 1.5,
          fontSize: 14,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            isLanHost ? '继续留在本局' : '继续游戏',
            style: const TextStyle(
              color: PartyColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isLanHost ? PartyColors.wolfRed : PartyColors.bgElevated,
            foregroundColor: Colors.white,
          ),
          child: Text(isLanHost ? '解散并退出' : '暂时退出'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await controller.leaveRoom();
  }
}

/// Intercepts Android system back gestures / hardware back button while inside
/// a room and routes them through [confirmLeaveRoom].
class RoomPopGuard extends StatelessWidget {
  const RoomPopGuard({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        confirmLeaveRoom(context, controller);
      },
      child: child,
    );
  }
}

/// Shows the LAN Host's QR code & screen-awake control mid-game so any friend
/// who accidentally closed their browser can re-scan and jump right back into
/// their original seat.
void showLanReconnectQrDialog(
  BuildContext context,
  AppController controller,
) {
  final endpoint = controller.endpointInfo;
  final snap = controller.snapshot;
  final webUrl = endpoint?.lanWebUrl ?? endpoint?.lanWsUrl;
  if (webUrl == null || snap == null) return;

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) => AlertDialog(
        backgroundColor: PartyColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.qr_code_2, color: PartyColors.gold),
            const SizedBox(width: 8),
            Text(
              '断线重连二维码 · 房号 ${snap.roomCode}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '朋友不小心关了浏览器？用手机相机重新扫此码即可 1 秒无缝回到原座位，手牌与身份全部保留！',
                style: TextStyle(
                  fontSize: 12.5,
                  color: PartyColors.textSecondary,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: QrImageView(
                  data: webUrl,
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: webUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制局域网重连网址')),
                  );
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: PartyColors.bgSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: PartyColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          webUrl,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: PartyColors.gold,
                            fontSize: 12.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy, size: 15, color: PartyColors.gold),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: PartyColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PartyColors.border),
                ),
                child: SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: const Text(
                    '房主屏幕常亮（防锁屏断线）',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    '保持亮屏可避免安卓省电冻结主机服务',
                    style: TextStyle(fontSize: 11, color: PartyColors.textMuted),
                  ),
                  value: controller.keepScreenAwake,
                  activeThumbColor: PartyColors.gold,
                  onChanged: (_) {
                    controller.toggleKeepScreenAwake();
                    setModalState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭', style: TextStyle(color: PartyColors.gold)),
          ),
        ],
      ),
    ),
  );
}

/// Compact AppBar action shown only for the LAN Host so disconnected friends
/// can re-scan the room QR code at any moment during a game.
class LanReconnectQrButton extends StatelessWidget {
  const LanReconnectQrButton({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.isLanHost) return const SizedBox.shrink();
    return IconButton(
      tooltip: '断线重连二维码 / 屏幕常亮',
      icon: const Icon(Icons.qr_code_2, color: PartyColors.gold),
      onPressed: () => showLanReconnectQrDialog(context, controller),
    );
  }
}
