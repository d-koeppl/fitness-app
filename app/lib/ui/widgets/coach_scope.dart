// What the coach chat can see, as a bar above the transcript that is one
// line until you open it — the port of fitness-dashboard's
// web/components/CoachScope.tsx and the chips of CoachAttachments.tsx.
//
// Above the transcript rather than at the composer, because these settings
// describe the whole conversation: they are stored per chat (ADR-017) and
// every turn is answered from them. Read on every turn, changed rarely, so
// a line that says what is on is enough until there is something to change.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/coach.dart';
import '../../domain/coach.dart';
import '../sheets/coach_sheets.dart';
import '../sheets/detail_sheet.dart';
import '../theme/palette.dart';

class CoachScopeBar extends ConsumerStatefulWidget {
  const CoachScopeBar({super.key, required this.budgetDetail});

  /// The day's Gemini budget spelled out; null until it has been read.
  final String? budgetDetail;

  @override
  ConsumerState<CoachScopeBar> createState() => _CoachScopeBarState();
}

class _CoachScopeBarState extends ConsumerState<CoachScopeBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final coach = ref.watch(coachProvider);
    final controller = ref.read(coachProvider.notifier);
    final flags = coach.flags;
    // Pinned chips are labelled from the picker's list when it has been
    // fetched; a chip still reads right without it (attachedLabel).
    final sessions = coach.attached.isEmpty && !_open
        ? const []
        : (ref.watch(attachableSessionsProvider).value ?? const []);
    final byId = {for (final s in sessions) s.id: s};

    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(Shape.xl),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 16, color: p.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      scopeSummary(flags, coach.lookback, coach.attached.length),
                      semanticsLabel:
                          'What this chat can see: ${scopeSummary(flags, coach.lookback, coach.attached.length)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.expand_more, size: 20, color: p.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            // Capped, and scrolling past the cap: an uncapped panel eats the
            // transcript on a short phone, and the conversation being
            // configured should stay on screen while it is.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(height: 1, color: p.outlineVariant.withValues(alpha: 0.5)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final key in IncludeKey.values)
                          _Pill(
                            label: '${isIncluded(flags, key) ? '✓ ' : ''}${key.label}',
                            selected: isIncluded(flags, key),
                            selectedBg: p.secondary.container,
                            selectedFg: p.secondary.onContainer,
                            onTap: () => controller.setInclude(toggleInclude(flags, key)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // One choice out of six, so the selected one is filled
                    // with the primary rather than the switches' tint.
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('How far back', style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant)),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final days in lookbackOptions)
                              Semantics(
                                label: lookbackLabel(days),
                                excludeSemantics: true,
                                child: _Pill(
                                  label: lookbackLabels(days).short,
                                  small: true,
                                  selected: days == coach.lookback,
                                  selectedBg: p.primary.color,
                                  selectedFg: p.primary.on,
                                  onTap: () => controller.setLookback(days),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // The workouts sent in full (ADR-021): their own row,
                    // because they name individual sessions rather than a
                    // kind of data.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in coach.attached)
                          Material(
                            color: p.tertiary.container,
                            borderRadius: BorderRadius.circular(Shape.sm),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(Shape.sm),
                              onTap: () => controller.toggleWorkout(id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: Text(
                                  '${attachedLabel(id, byId[id])}  ✕',
                                  semanticsLabel: 'Detach ${attachedLabel(id, byId[id])}',
                                  style: TypeScale.labelLarge.copyWith(color: p.tertiary.onContainer),
                                ),
                              ),
                            ),
                          ),
                        _Pill(
                          label: coach.attached.length >= coachMaxAttached
                              ? '$coachMaxAttached is the limit'
                              : '+ Add workout',
                          selected: false,
                          selectedBg: p.surface,
                          selectedFg: p.onSurface,
                          onTap: coach.attached.length >= coachMaxAttached
                              ? null
                              : () => openSheet(context, const WorkoutPickerSheet()),
                        ),
                      ],
                    ),
                    if (widget.budgetDetail != null) ...[
                      const SizedBox(height: 14),
                      Text(widget.budgetDetail!, style: TypeScale.labelSmall.copyWith(color: p.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.selectedBg,
    required this.selectedFg,
    required this.onTap,
    this.small = false,
  });

  final String label;
  final bool selected;
  final Color selectedBg;
  final Color selectedFg;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Shape.sm),
      side: selected ? BorderSide.none : BorderSide(color: p.outlineVariant),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Material(
          color: selected ? selectedBg : Colors.transparent,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: small
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                label,
                style: (small ? TypeScale.labelMedium : TypeScale.labelLarge).copyWith(
                  color: selected ? selectedFg : p.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
