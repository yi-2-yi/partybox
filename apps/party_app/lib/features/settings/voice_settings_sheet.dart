import 'package:material_ui/material_ui.dart';

import '../../core/audio/narrator_service.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/party_theme.dart';

/// Interactive bottom sheet letting users customize TTS voice, style preset,
/// speed/pitch/volume, broadcast scope, and Werewolf custom scripts + preview.
Future<void> showVoiceSettingsSheet(
  BuildContext context,
  AppController controller,
) async {
  final voices = await controller.narrator.fetchChineseVoices();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PartyColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _VoiceSettingsBody(
      controller: controller,
      voices: voices,
    ),
  );
}

class _VoiceSettingsBody extends StatefulWidget {
  const _VoiceSettingsBody({
    required this.controller,
    required this.voices,
  });

  final AppController controller;
  final List<DeviceVoiceOption> voices;

  @override
  State<_VoiceSettingsBody> createState() => _VoiceSettingsBodyState();
}

class _VoiceSettingsBodyState extends State<_VoiceSettingsBody> {
  late VoiceSettings _draft;
  late final Map<String, TextEditingController> _scriptControllers;

  @override
  void initState() {
    super.initState();
    _draft = widget.controller.voiceSettings;
    _scriptControllers = {
      for (final entry in VoiceSettings.defaultScripts.entries)
        entry.key: TextEditingController(
          text: _draft.customScripts[entry.key] ?? entry.value,
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _scriptControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPreset(String id, {required double rate, required double pitch}) {
    setState(() {
      _draft = _draft.copyWith(
        stylePreset: id,
        speechRate: rate,
        pitch: pitch,
      );
    });
  }

  Map<String, String> _collectCustomScripts() {
    final map = <String, String>{};
    for (final entry in _scriptControllers.entries) {
      final text = entry.value.text.trim();
      final def = VoiceSettings.defaultScripts[entry.key];
      if (text.isNotEmpty && text != def) {
        map[entry.key] = text;
      }
    }
    return map;
  }

  Future<void> _previewVoice() async {
    final previewSettings = _draft.copyWith(
      enabled: true,
      customScripts: _collectCustomScripts(),
    );
    await widget.controller.updateVoiceSettings(previewSettings);
    final sample =
        _scriptControllers['night_wolf']?.text.trim().isNotEmpty == true
            ? _scriptControllers['night_wolf']!.text.trim()
            : '天黑请闭眼，狼人请睁眼，确认队友并选择今晚要袭击的玩家。';
    await widget.controller.narrator.speak(sample);
  }

  Future<void> _saveAndClose() async {
    final next = _draft.copyWith(customScripts: _collectCustomScripts());
    await widget.controller.updateVoiceSettings(next);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (ctx, scrollController) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over, color: PartyColors.gold),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '法官语音自定义设置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: _previewVoice,
                  icon: const Icon(Icons.play_circle_outline,
                      color: PartyColors.gold),
                  label: const Text('试听'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开启语音法官播报'),
              value: _draft.enabled,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(enabled: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅房主手机外放（推荐）'),
              subtitle: const Text(
                '关闭后，所有加入房间的手机都会同步播报语音',
                style: TextStyle(fontSize: 12, color: PartyColors.textSecondary),
              ),
              value: _draft.hostOnlyBroadcast,
              onChanged: (v) => setState(
                () => _draft = _draft.copyWith(hostOnlyBroadcast: v),
              ),
            ),

            const Divider(color: PartyColors.border),
            const SizedBox(height: 6),

            const Text(
              '一键声线风格',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('悬疑低沉法官'),
                  selected: _draft.stylePreset == 'mystery',
                  selectedColor: PartyColors.goldSoft,
                  onSelected: (_) =>
                      _applyPreset('mystery', rate: 0.42, pitch: 0.82),
                ),
                ChoiceChip(
                  label: const Text('活力聚会主持'),
                  selected: _draft.stylePreset == 'party',
                  selectedColor: PartyColors.goldSoft,
                  onSelected: (_) =>
                      _applyPreset('party', rate: 0.50, pitch: 1.02),
                ),
                ChoiceChip(
                  label: const Text('可爱动漫声线'),
                  selected: _draft.stylePreset == 'anime',
                  selectedColor: PartyColors.goldSoft,
                  onSelected: (_) =>
                      _applyPreset('anime', rate: 0.55, pitch: 1.28),
                ),
              ],
            ),

            if (widget.voices.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                '选择本机中文音色',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: widget.voices.any((v) => v.name == _draft.voiceName)
                    ? _draft.voiceName
                    : null,
                dropdownColor: PartyColors.bgCard,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('系统默认中文语音'),
                  ),
                  ...widget.voices.map(
                    (v) => DropdownMenuItem<String?>(
                      value: v.name,
                      child: Text(
                        '${v.name} (${v.locale})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (selectedName) {
                  if (selectedName == null) {
                    setState(() => _draft = _draft.copyWith(clearVoice: true));
                  } else {
                    final match =
                        widget.voices.firstWhere((v) => v.name == selectedName);
                    setState(() {
                      _draft = _draft.copyWith(
                        voiceName: match.name,
                        voiceLocale: match.locale,
                      );
                    });
                  }
                },
              ),
            ],

            const SizedBox(height: 12),
            _LabeledSlider(
              label: '语速',
              valueLabel: '${(_draft.speechRate * 2).toStringAsFixed(2)}x',
              value: _draft.speechRate.clamp(0.3, 0.8),
              min: 0.3,
              max: 0.8,
              onChanged: (v) => setState(
                () => _draft = _draft.copyWith(
                  speechRate: v,
                  stylePreset: 'custom',
                ),
              ),
            ),
            _LabeledSlider(
              label: '音调',
              valueLabel: _draft.pitch.toStringAsFixed(2),
              value: _draft.pitch.clamp(0.65, 1.45),
              min: 0.65,
              max: 1.45,
              onChanged: (v) => setState(
                () => _draft = _draft.copyWith(pitch: v, stylePreset: 'custom'),
              ),
            ),
            _LabeledSlider(
              label: '音量',
              valueLabel: '${(_draft.volume * 100).round()}%',
              value: _draft.volume.clamp(0.2, 1.0),
              min: 0.2,
              max: 1.0,
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(volume: v)),
            ),

            const Divider(color: PartyColors.border),
            Row(
              children: [
                const Text(
                  '自定义狼人杀播报台词',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      for (final e in VoiceSettings.defaultScripts.entries) {
                        _scriptControllers[e.key]?.text = e.value;
                      }
                      _draft = _draft.copyWith(customScripts: const {});
                    });
                  },
                  child: const Text('恢复默认'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...VoiceSettings.defaultScriptLabels.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _scriptControllers[e.key],
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: e.value,
                    isDense: true,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveAndClose,
                icon: const Icon(Icons.check),
                label: const Text('保存语音设置'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: PartyColors.gold,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              color: PartyColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
