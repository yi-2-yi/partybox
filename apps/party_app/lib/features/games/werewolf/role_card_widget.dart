import 'package:material_ui/material_ui.dart';
import 'package:party_core/party_core.dart';

import '../../../core/theme/party_theme.dart';

Color roleAccentColor(WerewolfRole role) => switch (role) {
      WerewolfRole.werewolf => PartyColors.wolfRed,
      WerewolfRole.seer => PartyColors.seerCyan,
      WerewolfRole.witch => PartyColors.witchPurple,
      WerewolfRole.hunter => const Color(0xFFFB923C),
      WerewolfRole.guard => PartyColors.guardGreen,
      WerewolfRole.idiot => const Color(0xFFFACC15),
      WerewolfRole.villager => PartyColors.textSecondary,
    };

IconData roleIcon(WerewolfRole role) => switch (role) {
      WerewolfRole.werewolf => Icons.pets,
      WerewolfRole.seer => Icons.visibility,
      WerewolfRole.witch => Icons.science,
      WerewolfRole.hunter => Icons.gps_fixed,
      WerewolfRole.guard => Icons.shield,
      WerewolfRole.idiot => Icons.theater_comedy,
      WerewolfRole.villager => Icons.person,
    };

/// Anti-peek press-and-hold identity card designed for in-person party play.
/// Holding reveals your secret role; releasing immediately flips it face down.
class RolePeekCard extends StatefulWidget {
  const RolePeekCard({
    super.key,
    required this.role,
    required this.seatNumber,
    this.teammateLabels = const [],
  });

  final WerewolfRole role;
  final int seatNumber;
  final List<String> teammateLabels;

  @override
  State<RolePeekCard> createState() => _RolePeekCardState();
}

class _RolePeekCardState extends State<RolePeekCard> {
  bool _revealed = false;

  void _setRevealed(bool value) {
    if (_revealed == value) return;
    setState(() => _revealed = value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccentColor(widget.role);

    return GestureDetector(
      onTapDown: (_) => _setRevealed(true),
      onTapUp: (_) => _setRevealed(false),
      onTapCancel: () => _setRevealed(false),
      onLongPressStart: (_) => _setRevealed(true),
      onLongPressEnd: (_) => _setRevealed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: _revealed
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.28),
                    PartyColors.bgCard,
                  ],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E2A4A),
                    Color(0xFF111930),
                  ],
                ),
          border: Border.all(
            color: _revealed ? accent : PartyColors.gold.withValues(alpha: 0.5),
            width: _revealed ? 2 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: (_revealed ? accent : PartyColors.gold).withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: _revealed ? _buildFront(accent) : _buildBack(),
      ),
    );
  }

  Widget _buildBack() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: PartyColors.goldSoft,
            border: Border.all(color: PartyColors.gold.withValues(alpha: 0.6)),
          ),
          child: const Icon(Icons.fingerprint, size: 34, color: PartyColors.gold),
        ),
        const SizedBox(height: 14),
        Text(
          '${widget.seatNumber}号 身份牌（已隐藏）',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: PartyColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '长按卡片查看身份，松手立即防偷窥遮挡',
          style: TextStyle(fontSize: 13, color: PartyColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFront(Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(roleIcon(widget.role), color: accent, size: 30),
            const SizedBox(width: 10),
            Text(
              widget.role.displayName,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${widget.seatNumber}号 · ${widget.role.campName}',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.role.description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: PartyColors.textPrimary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        if (widget.teammateLabels.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '狼队友：${widget.teammateLabels.join("、")}',
            style: const TextStyle(
              color: PartyColors.wolfRed,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}
