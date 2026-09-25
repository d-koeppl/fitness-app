// Chat with Gemini about your own data — the port of fitness-dashboard's
// web/components/tabs/CoachTab.tsx. State and requests are in
// lib/data/coach.dart; the pure parts in lib/domain/coach.dart.
//
// The tab fills the space the shell gives it rather than scrolling as a
// page: the transcript scrolls inside itself, and the composer stays put
// at the bottom. From the top: which chat you are in, what is left of the
// day's budget and a new chat; what the chat can see, one line until
// opened (ui/widgets/coach_scope.dart); the transcript; any error, outside
// the scroller so it cannot scroll out of sight; the composer.

import 'package:fitness_api/fitness_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/coach.dart';
import '../../domain/coach.dart';
import '../sheets/coach_sheets.dart';
import '../sheets/detail_sheet.dart';
import '../theme/palette.dart';
import '../widgets/coach_scope.dart';
import '../widgets/report_text.dart';

class CoachTab extends ConsumerStatefulWidget {
  const CoachTab({super.key});

  @override
  ConsumerState<CoachTab> createState() => _CoachTabState();
}

class _CoachTabState extends ConsumerState<CoachTab> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Built the first time the tab is opened (the shell keeps it after).
    Future.microtask(() => ref.read(coachProvider.notifier).ensureLoaded());
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    final coach = ref.read(coachProvider);
    if (coach.sending || coach.exhausted) return;
    _input.clear();
    ref.read(coachProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final coach = ref.watch(coachProvider);
    // A failed message comes back to the composer, to send again as it was.
    ref.listen(coachProvider.select((s) => s.draft), (previous, next) {
      if (next != null && !identical(next, previous)) {
        _input.text = next.text;
        _input.selection = TextSelection.collapsed(offset: next.text.length);
      }
    });
    // A question sent while scrolled up into the chat brings the view back
    // down to it, and to the reply that follows.
    ref.listen(coachProvider.select((s) => (s.pending, s.messages.length, s.activeId)), (_, _) {
      if (_scroll.hasClients && _scroll.offset > 0) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
    final budget = coach.usage == null ? null : budgetChip(coach.usage!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(coach: coach, budget: budget),
        const SizedBox(height: 8),
        CoachScopeBar(budgetDetail: budget?.detail),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Shape.xl)),
            clipBehavior: Clip.antiAlias,
            child: _Transcript(coach: coach, scroll: _scroll),
          ),
        ),
        if (coach.error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: p.error.container, borderRadius: BorderRadius.circular(Shape.lg)),
            child: Text(coach.error!, style: TypeScale.bodyMedium.copyWith(color: p.error.onContainer)),
          ),
        ],
        const SizedBox(height: 8),
        _Composer(
          controller: _input,
          focus: _focus,
          exhausted: coach.exhausted,
          sending: coach.sending,
          onSend: _send,
        ),
      ],
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.coach, required this.budget});

  final CoachState coach;
  final ({String label, BudgetTone tone, String detail})? budget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final tone = budget?.tone;
    final (chipBg, chipFg) = switch (tone) {
      BudgetTone.low => (p.warning.container, p.warning.onContainer),
      BudgetTone.spent => (p.error.container, p.error.onContainer),
      _ => (p.surfaceContainerHigh, p.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Shape.xl)),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: p.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Shape.sm),
              child: InkWell(
                borderRadius: BorderRadius.circular(Shape.sm),
                onTap: () => openSheet(context, const CoachConversationsSheet()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    conversationLabel(coach.active),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.labelLarge.copyWith(color: p.onSurface),
                  ),
                ),
              ),
            ),
          ),
          if (budget != null) ...[
            const SizedBox(width: 8),
            // The number only; the rest is at the foot of the scope panel.
            Tooltip(
              message: budget!.detail,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(99)),
                child: Text(
                  budget!.label,
                  style: TypeScale.labelSmall.copyWith(color: chipFg, fontFeatures: TypeScale.tabular),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'New chat',
            onPressed: ref.read(coachProvider.notifier).newChat,
            style: IconButton.styleFrom(backgroundColor: p.primary.container, foregroundColor: p.primary.onContainer),
            icon: const Icon(Icons.add, size: 20),
          ),
        ],
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.coach, required this.scroll});

  final CoachState coach;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (coach.loadingChat) {
      return Center(
        child: Text('Loading chat…', style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant)),
      );
    }
    if (coach.messages.isEmpty && !coach.sending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: p.primary.container, shape: BoxShape.circle),
                child: Icon(Icons.auto_awesome, color: p.primary.onContainer, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                'Ask about how to prepare for your next match, trends in your data, or when to add extra training.',
                textAlign: TextAlign.center,
                style: TypeScale.bodyLarge.copyWith(color: p.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    // Newest at the bottom, and the list anchored there: reversed, so a new
    // turn, the "Thinking…" bubble and a freshly opened chat all land in
    // view without scrolling by hand.
    final items = <Widget>[
      for (final message in coach.messages) _Bubble(key: ValueKey(message.id), message: message),
      if (coach.pending != null) ...[
        _Bubble.mine(key: const ValueKey('pending'), text: coach.pending!),
        const _Thinking(key: ValueKey('thinking')),
      ],
    ];
    return ListView.separated(
      controller: scroll,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => items[items.length - 1 - i],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required ChatMessageOut this.message}) : text = null;
  const _Bubble.mine({super.key, required String this.text}) : message = null;

  final ChatMessageOut? message;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mine = message == null || message!.role == 'user';
    final content = text ?? message!.content;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          // A reply gets a little more room: it may hold a table or a chart.
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * (mine ? 0.85 : 0.92)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? p.primary.color : p.surfaceContainerHigh,
              borderRadius: mine
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(6),
                    )
                  : const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(20),
                    ),
            ),
            // Your own message exactly as typed — through the markdown
            // parser it would lose any asterisk or # you meant. The coach
            // answers in markdown, through the daily report's renderer.
            child: mine
                ? SelectableText(content, style: TypeScale.bodyLarge.copyWith(color: p.primary.on))
                : SelectionArea(child: ReportText(content)),
          ),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: p.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
        child: Text('Thinking…', style: TypeScale.bodyLarge.copyWith(color: p.onSurfaceVariant)),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.exhausted,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool exhausted;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          // Enter sends, Shift+Enter starts a new line — on a keyboard. On a
          // phone the keyboard's own send key does.
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.enter): onSend},
            child: TextField(
              controller: controller,
              focusNode: focus,
              enabled: !exhausted,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: TypeScale.bodyLarge.copyWith(color: p.onSurface),
              decoration: InputDecoration(
                hintText: exhausted ? 'No messages left today' : 'Ask your coach…',
                filled: true,
                fillColor: p.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: sending || exhausted ? null : onSend,
            style: FilledButton.styleFrom(backgroundColor: p.primary.color, foregroundColor: p.primary.on),
            child: const Text('Send'),
          ),
        ),
      ],
    );
  }
}
