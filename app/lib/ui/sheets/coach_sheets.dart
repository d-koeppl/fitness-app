// The coach's two pickers, in the app's one overlay idiom (DetailSheet) —
// the port of fitness-dashboard's web/components/CoachConversations.tsx and
// the WorkoutPicker in CoachAttachments.tsx.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/coach.dart';
import '../../data/dashboard.dart';
import '../../domain/coach.dart';
import '../../domain/format.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';
import 'detail_sheet.dart';

/// The stored chats, most recently used first. Delete confirms in place:
/// the row's button becomes "Delete?" and takes a second tap.
class CoachConversationsSheet extends ConsumerStatefulWidget {
  const CoachConversationsSheet({super.key});

  @override
  ConsumerState<CoachConversationsSheet> createState() => _CoachConversationsSheetState();
}

class _CoachConversationsSheetState extends ConsumerState<CoachConversationsSheet> {
  int? _confirming;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final coach = ref.watch(coachProvider);
    final controller = ref.read(coachProvider.notifier);
    return DetailSheet(
      title: 'Chats',
      children: [
        if (coach.conversations.isEmpty) const Notice('No chats yet. Ask something to start one.'),
        if (coach.conversations.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(Shape.lg),
            child: Column(
              children: [
                for (final conv in coach.conversations) ...[
                  Material(
                    color: conv.id == coach.activeId ? p.secondary.container : p.surface,
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).maybePop();
                              controller.open(conv.id);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      conversationLabel(conv),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TypeScale.bodyMedium.copyWith(
                                        color: conv.id == coach.activeId ? p.secondary.onContainer : p.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    fmtDate(conv.updatedAt),
                                    style: TypeScale.labelSmall.copyWith(
                                      color: conv.id == coach.activeId ? p.secondary.onContainer : p.onSurfaceVariant,
                                      fontFeatures: TypeScale.tabular,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _confirming == conv.id
                              ? TextButton(
                                  style: TextButton.styleFrom(
                                    backgroundColor: p.error.container,
                                    foregroundColor: p.error.onContainer,
                                  ),
                                  onPressed: () {
                                    setState(() => _confirming = null);
                                    controller.remove(conv.id);
                                  },
                                  child: const Text('Delete?'),
                                )
                              : IconButton(
                                  tooltip: 'Delete ${conversationLabel(conv)}',
                                  onPressed: () => setState(() => _confirming = conv.id),
                                  icon: Icon(Icons.delete_outline, size: 18, color: p.onSurfaceVariant),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Pick the workouts to send in full. Multi-select, and the sheet stays
/// open as you tap: the question this is for is usually comparative.
class WorkoutPickerSheet extends ConsumerWidget {
  const WorkoutPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final attached = ref.watch(coachProvider.select((s) => s.attached));
    final controller = ref.read(coachProvider.notifier);
    final sessions = ref.watch(attachableSessionsProvider);
    final full = attached.length >= coachMaxAttached;
    final list = sessions.value ?? const [];

    return DetailSheet(
      title: 'Attach workouts',
      children: [
        Text(
          'The coach gets everything about the ones you pick — every number the watch recorded, and the whole '
          'heart rate trace, not just the average.${full ? ' $coachMaxAttached is the most one chat can hold.' : ''}',
          style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant),
        ),
        if (sessions.isLoading) const Notice('Loading your workouts…'),
        if (sessions.hasError)
          Text(describeError(sessions.error!), style: TypeScale.labelMedium.copyWith(color: p.error.color)),
        if (!sessions.isLoading && !sessions.hasError && list.isEmpty)
          const Notice('No sessions tracked yet — there is nothing to attach.'),
        if (list.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(Shape.lg),
            child: Column(
              children: [
                for (final session in list) ...[
                  Builder(
                    builder: (context) {
                      final on = attached.contains(session.id);
                      // Only a tracked session has a trace to send. Still
                      // attachable, but the row says which it is.
                      final tracked = session.source_ == 'tracked';
                      final start = session.startTs;
                      final fg = on ? p.secondary.onContainer : p.onSurface;
                      return Opacity(
                        opacity: full && !on ? 0.5 : 1,
                        child: Material(
                          color: on ? p.secondary.container : p.surface,
                          child: InkWell(
                            // Full means nothing more goes in; anything in
                            // can still come out.
                            onTap: full && !on ? null : () => controller.toggleWorkout(session.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    child: Text(on ? '✓' : '', style: TypeScale.labelLarge.copyWith(color: fg)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sessionTitle(session),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TypeScale.bodyMedium.copyWith(color: fg),
                                        ),
                                        Text(
                                          '${fmtDate(session.date)}'
                                          '${start != null ? ' · ${fmtTime(start)}' : ''}'
                                          ' · ${fmtDuration(session.durationMinutes)} · ${fmtSessionLoad(session)}'
                                          '${tracked ? '' : ' · no heart rate recorded'}',
                                          style: TypeScale.labelSmall.copyWith(
                                            color: on ? p.secondary.onContainer : p.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
