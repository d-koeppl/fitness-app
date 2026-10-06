// The popup New report opens first: how the user feels today, and how
// strongly. The answer rides along with the one report it was given for
// (POST /reports/generate) and is stored nowhere.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// The feelings on offer, in the order shown, with the palette role each
/// one's chip is tinted by. The server's enum has the same eight values.
const _feelings = <(CheckInInFeelingEnum, String)>[
  (CheckInInFeelingEnum.energised, 'Energised'),
  (CheckInInFeelingEnum.good, 'Good'),
  (CheckInInFeelingEnum.okay, 'Okay'),
  (CheckInInFeelingEnum.tired, 'Tired'),
  (CheckInInFeelingEnum.stressed, 'Stressed'),
  (CheckInInFeelingEnum.sore, 'Sore'),
  (CheckInInFeelingEnum.ill, 'Ill'),
  (CheckInInFeelingEnum.cold, 'Having a cold'),
  (CheckInInFeelingEnum.other, 'Other'),
];

const _strengthNames = ['very mild', 'mild', 'medium', 'strong', 'very strong'];

Role _roleFor(Palette p, CheckInInFeelingEnum feeling) => switch (feeling) {
  CheckInInFeelingEnum.energised || CheckInInFeelingEnum.sore => p.warning,
  CheckInInFeelingEnum.good => p.success,
  CheckInInFeelingEnum.okay => p.primary,
  CheckInInFeelingEnum.tired || CheckInInFeelingEnum.cold || CheckInInFeelingEnum.other => p.secondary,
  CheckInInFeelingEnum.stressed => p.tertiary,
  CheckInInFeelingEnum.ill || CheckInInFeelingEnum.unknownDefaultOpenApi => p.error,
};

/// Ask how the user feels. Resolves to the answer, or null if they backed
/// out (Cancel, the back button, a tap outside) — in which case no report
/// should be made.
Future<CheckInIn?> askCheckIn(BuildContext context) =>
    showDialog<CheckInIn>(context: context, builder: (_) => const CheckInDialog());

class CheckInDialog extends StatefulWidget {
  const CheckInDialog({super.key});

  @override
  State<CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<CheckInDialog> {
  CheckInInFeelingEnum? _feeling;
  int? _strength;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Both chosen, and the user's own words typed if that is what they chose.
  bool get _complete =>
      _feeling != null && _strength != null && (_feeling != CheckInInFeelingEnum.other || _note.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final feeling = _feeling;
    final strength = _strength;
    final label = TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant, letterSpacing: 0.5);

    return Dialog(
      backgroundColor: p.surfaceContainerLowest,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Shape.xl)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How do you feel today?', style: TypeScale.headlineSmall.copyWith(color: p.onSurface)),
              const SizedBox(height: 4),
              Text('This goes into your new report.', style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant)),
              const SizedBox(height: 20),
              Text('FEELING', style: label),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (value, name) in _feelings)
                    _ChoiceChip(
                      label: name,
                      selected: feeling == value,
                      bg: _roleFor(p, value).container,
                      fg: _roleFor(p, value).onContainer,
                      onTap: () => setState(() => _feeling = value),
                    ),
                ],
              ),
              if (feeling == CheckInInFeelingEnum.other) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  autofocus: true,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'How do you feel?', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                strength == null ? 'HOW STRONG?' : 'HOW STRONG?  ${_strengthNames[strength - 1].toUpperCase()}',
                style: label,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var n = 1; n <= 5; n++) ...[
                    if (n > 1) const SizedBox(width: 8),
                    Expanded(
                      child: _StrengthButton(
                        n: n,
                        filled: strength != null && n <= strength,
                        current: strength == n,
                        onTap: () => setState(() => _strength = n),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Barely', style: TypeScale.bodySmall.copyWith(color: p.onSurfaceVariant)),
                  Text('Very strong', style: TypeScale.bodySmall.copyWith(color: p.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  FilledButton(
                    onPressed: !_complete
                        ? null
                        : () => Navigator.of(context).pop(
                            CheckInIn(
                              feeling: feeling!,
                              strength: strength!,
                              note: feeling == CheckInInFeelingEnum.other ? _note.text.trim() : null,
                            ),
                          ),
                    child: const Text('Save and create report'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A feeling. Unselected it is the role's tonal container; selected the two
/// colours swap, which keeps the text readable in both themes.
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? fg : bg,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text(label, style: TypeScale.labelLarge.copyWith(color: selected ? bg : fg, fontSize: 15))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One step of the 1–5 scale. The steps up to the chosen one are filled, so
/// the row reads as a meter.
class _StrengthButton extends StatelessWidget {
  const _StrengthButton({required this.n, required this.filled, required this.current, required this.onTap});

  final int n;
  final bool filled;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: current,
      label: '$n of 5, ${_strengthNames[n - 1]}',
      excludeSemantics: true,
      child: Material(
        color: filled ? p.primary.color : p.primary.container,
        borderRadius: BorderRadius.circular(Shape.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(Shape.lg),
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Center(
              child: Text(
                '$n',
                style: TypeScale.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                  color: filled ? p.primary.on : p.primary.onContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
