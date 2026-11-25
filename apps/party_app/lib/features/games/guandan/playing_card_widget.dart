import 'package:material_ui/material_ui.dart';
import 'package:party_core/party_core.dart';

import '../../../core/theme/party_theme.dart';

/// Tactile poker card widget for Guandan with level-card and Heart-wildcard highlights.
class PlayingCardWidget extends StatelessWidget {
  const PlayingCardWidget({
    super.key,
    required this.card,
    required this.currentLevel,
    this.selected = false,
    this.mini = false,
    this.onTap,
  });

  final PlayingCard card;
  final int currentLevel;
  final bool selected;
  final bool mini;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isWild = card.isWildcard(currentLevel);
    final isLevel = card.isLevelCard(currentLevel);
    final isRed = card.isBigJoker || card.suit.isRed;

    final width = mini ? 42.0 : 52.0;
    final height = mini ? 58.0 : 76.0;

    final rankColor = card.isBigJoker
        ? const Color(0xFFD92D4B)
        : card.isSmallJoker
            ? const Color(0xFF1F2937)
            : isRed
                ? const Color(0xFFD92D4B)
                : const Color(0xFF141B2D);

    final bgColor = isWild
        ? const Color(0xFFFFF8E1)
        : card.isBigJoker
            ? const Color(0xFFFFF1F2)
            : const Color(0xFFFAF9F5);

    final borderColor = selected
        ? PartyColors.gold
        : isWild
            ? const Color(0xFFE5A00D)
            : isLevel
                ? PartyColors.seerCyan
                : const Color(0xFFCBD5E1);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.translationValues(0, selected ? -12 : 0, 0),
        width: width,
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: mini ? 3 : 4,
          vertical: mini ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(mini ? 7 : 9),
          border: Border.all(
            color: borderColor,
            width: selected ? 2.4 : (isWild ? 1.8 : 1.0),
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? PartyColors.gold.withValues(alpha: 0.45)
                  : Colors.black.withValues(alpha: 0.35),
              blurRadius: selected ? 10 : 4,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      card.isJoker ? (card.isBigJoker ? '大' : '小') : card.rankLabel,
                      style: TextStyle(
                        color: rankColor,
                        fontSize: mini ? 12 : 14,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      card.isJoker ? '王' : card.suit.symbol,
                      style: TextStyle(
                        color: rankColor,
                        fontSize: mini ? 11 : 13,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
                if (!mini)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      card.isJoker ? '★' : card.suit.symbol,
                      style: TextStyle(
                        color: rankColor.withValues(alpha: 0.25),
                        fontSize: 20,
                        height: 1.0,
                      ),
                    ),
                  ),
              ],
            ),
            if (isWild)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '配',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: mini ? 8 : 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
            else if (isLevel && !mini)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '级',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
