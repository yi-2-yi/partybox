import 'package:material_ui/material_ui.dart';

import '../theme/party_theme.dart';

enum AvatarCategory {
  animal,
  anime;

  String get label => switch (this) {
        AvatarCategory.animal => '小动物系列',
        AvatarCategory.anime => '动漫人物系列',
      };
}

class PartyAvatar {
  const PartyAvatar({
    required this.index,
    required this.emoji,
    required this.name,
    required this.category,
    required this.gradientColors,
  });

  final int index;
  final String emoji;
  final String name;
  final AvatarCategory category;
  final List<Color> gradientColors;
}

/// 16 built-in animal & anime-character avatars (zero upload required).
class PartyAvatars {
  static const List<PartyAvatar> all = [
    // 8 Cute Animals (0..7)
    PartyAvatar(
      index: 0,
      emoji: '🦊',
      name: '小狐狸',
      category: AvatarCategory.animal,
      gradientColors: [Color(0xFFF97316), Color(0xFF9A3412)],
    ),
    PartyAvatar(
      index: 1,
      emoji: '🐺',
      name: '森林孤狼',
      category: AvatarCategory.animal,
      gradientColors: [Color(0xFF64748B), Color(0xFF1E293B)],
    ),
    PartyAvatar(
      index: 2,
      emoji: '🐱',
      name: '软萌橘猫',
      category: AvatarCategory.animal,
      gradientColors: [Color(0xFFFBBF24), Color(0xFFB45309)],
    ),
    PartyAvatar(
      index: 3,
      emoji: '🐶',
      name: '憨憨柴犬',
      category: AvatarCategory.animal,
      gradientColors: [Color(0xFFF59E0B), Color(0xFF78350F)],
    ),
    PartyAvatar(
      index: 4,
      emoji: '🐼',
      name: '功夫熊猫',
      category: AvatarCategory.animal,
      gradientColors: [Color(0xFF34D399), Color(0xFF065F46)],
    ),
    PartyAvatar(
      index: 5,
      emoji: '🐰',
      name: '软耳兔兔',
      category: AvatarCategory.animal,
      gradientColors: [Color(0xFFF472B6), Color(0xFF9D174D)],
    ),
    PartyAvatar(
      index: 6,
      emoji: '🦉',
      name: '暗夜猫头鹰',
      category: AvatarCategory.animal,
      gradientColors: [Color(0xFF818CF8), Color(0xFF312E81)],
    ),
    PartyAvatar(
      index: 7,
      emoji: '🐻',
      name: '蜂蜜棕熊',
      category: AvatarCategory.animal,
      gradientColors: [Color(0xFFD97706), Color(0xFF451A03)],
    ),

    // 8 Anime / RPG Characters (8..15)
    PartyAvatar(
      index: 8,
      emoji: '🧙',
      name: '神秘魔法师',
      category: AvatarCategory.anime,
      gradientColors: [Color(0xFFA855F7), Color(0xFF4C1D95)],
    ),
    PartyAvatar(
      index: 9,
      emoji: '🥷',
      name: '暗影忍者',
      category: AvatarCategory.anime,
      gradientColors: [Color(0xFF38BDF8), Color(0xFF0C4A6E)],
    ),
    PartyAvatar(
      index: 10,
      emoji: '🧝',
      name: '精灵射手',
      category: AvatarCategory.anime,
      gradientColors: [Color(0xFF10B981), Color(0xFF064E3B)],
    ),
    PartyAvatar(
      index: 11,
      emoji: '🦸',
      name: '热血英雄',
      category: AvatarCategory.anime,
      gradientColors: [Color(0xFFEF4444), Color(0xFF7F1D1D)],
    ),
    PartyAvatar(
      index: 12,
      emoji: '🕵️',
      name: '侦探少年',
      category: AvatarCategory.anime,
      gradientColors: [Color(0xFF6366F1), Color(0xFF1E1B4B)],
    ),
    PartyAvatar(
      index: 13,
      emoji: '🧚',
      name: '治愈精灵',
      category: AvatarCategory.anime,
      gradientColors: [Color(0xFFEC4899), Color(0xFF701A75)],
    ),
    PartyAvatar(
      index: 14,
      emoji: '🧛',
      name: '暗夜伯爵',
      category: AvatarCategory.anime,
      gradientColors: [Color(0xFFE11D48), Color(0xFF4C0519)],
    ),
    PartyAvatar(
      index: 15,
      emoji: '🤖',
      name: '机甲少年',
      category: AvatarCategory.anime,
      gradientColors: [Color(0xFF06B6D4), Color(0xFF164E63)],
    ),
  ];

  static PartyAvatar byIndex(int index) {
    final safe = index % all.length;
    return all[safe < 0 ? safe + all.length : safe];
  }
}

/// Circular gradient badge displaying the player's chosen animal/anime avatar.
class PartyAvatarWidget extends StatelessWidget {
  const PartyAvatarWidget({
    super.key,
    required this.avatarIndex,
    this.radius = 18,
    this.dimmed = false,
    this.borderColor,
  });

  final int avatarIndex;
  final double radius;
  final bool dimmed;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final avatar = PartyAvatars.byIndex(avatarIndex);
    return Opacity(
      opacity: dimmed ? 0.42 : 1.0,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: avatar.gradientColors,
          ),
          border: Border.all(
            color: borderColor ?? Colors.white.withValues(alpha: 0.28),
            width: borderColor != null ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          avatar.emoji,
          style: TextStyle(fontSize: radius * 1.08, height: 1.1),
        ),
      ),
    );
  }
}

class ProfileEditResult {
  const ProfileEditResult({required this.name, required this.avatarIndex});
  final String name;
  final int avatarIndex;
}

/// Opens a built-in nickname + 16 animal/anime avatar picker dialog.
Future<ProfileEditResult?> showProfileEditorDialog(
  BuildContext context, {
  required String currentName,
  required int currentAvatarIndex,
}) async {
  final nameCtrl = TextEditingController(text: currentName);
  var selectedIndex = currentAvatarIndex;

  return showDialog<ProfileEditResult>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          Widget buildGroup(AvatarCategory category) {
            final items =
                PartyAvatars.all.where((a) => a.category == category).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: PartyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: items.map((av) {
                    final isSelected = av.index == selectedIndex;
                    return InkWell(
                      onTap: () => setState(() => selectedIndex = av.index),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 68,
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? PartyColors.goldSoft
                              : PartyColors.bgSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                isSelected ? PartyColors.gold : PartyColors.border,
                            width: isSelected ? 1.8 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PartyAvatarWidget(
                              avatarIndex: av.index,
                              radius: 18,
                              borderColor: isSelected ? PartyColors.gold : null,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              av.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? PartyColors.gold
                                    : PartyColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          }

          return AlertDialog(
            backgroundColor: PartyColors.bgCard,
            title: Row(
              children: [
                PartyAvatarWidget(avatarIndex: selectedIndex, radius: 18),
                const SizedBox(width: 10),
                const Text('设置昵称与头像', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      maxLength: 12,
                      decoration: const InputDecoration(
                        labelText: '你的聚会昵称',
                        hintText: '例如：小明 / 阿杰',
                      ),
                    ),
                    const SizedBox(height: 8),
                    buildGroup(AvatarCategory.animal),
                    const SizedBox(height: 14),
                    buildGroup(AvatarCategory.anime),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final trimmed = nameCtrl.text.trim();
                  Navigator.pop(
                    ctx,
                    ProfileEditResult(
                      name: trimmed.isEmpty ? currentName : trimmed,
                      avatarIndex: selectedIndex,
                    ),
                  );
                },
                child: const Text('保存头像与昵称'),
              ),
            ],
          );
        },
      );
    },
  );
}
