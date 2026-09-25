// The coach tab's state and requests — the port of the state half of
// fitness-dashboard's web/components/tabs/CoachTab.tsx, with the attachable
// sessions of web/hooks/useAttachableSessions.ts.
//
// The toggles, the History and the pinned workouts are the whole request:
// the prompt and the data are assembled server-side, and the history lives
// there too (ADR-017), so a message names its conversation by id. Those
// settings are stored per conversation, so opening a chat restores them.
//
// Every message is one Gemini request out of a budget shared with the daily
// report (ADR-013); the count comes back with every reply. A message also
// carries an id of its own (ADR-035): a reply lost on the way back — the
// connection dropped while Gemini was still answering — is asked for again
// under the same id, and the server answers from what it stored instead of
// asking Gemini twice.

import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fitness_api/fitness_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/slow_requests.dart';
import '../domain/coach.dart';
import 'dashboard.dart';

class CoachState {
  const CoachState({
    this.loaded = false,
    this.usage,
    this.conversations = const [],
    this.activeId,
    this.messages = const [],
    this.pending,
    this.include,
    this.lookback = coachDefaultLookback,
    this.attached = const [],
    this.loadingChat = false,
    this.error,
    this.draft,
    this.openRequests = 0,
  });

  final bool loaded;

  /// Null until read; the composer stays enabled meanwhile, because the
  /// server is what enforces the cap and greying out a chat that still has
  /// messages left is the worse mistake.
  final CoachUsageOut? usage;
  final List<ConversationOut> conversations;
  final int? activeId;
  final List<ChatMessageOut> messages;

  /// The question being answered, shown at once under the transcript. Not a
  /// message yet: nothing is stored until the reply is.
  final String? pending;
  final IncludeFlags? include;
  final CoachLookbackDays lookback;

  /// The workouts pinned to the chat, by session id, in the order attached.
  final List<String> attached;
  final bool loadingChat;
  final String? error;

  /// A message that failed, handed back to the composer so it can be sent
  /// again without retyping. A new object each time, so the same text
  /// failing twice still reaches the composer.
  final ({String text})? draft;

  /// Bumped when something outside the tab (a session's "Ask the coach")
  /// wants the shell to switch to it.
  final int openRequests;

  bool get sending => pending != null;
  bool get exhausted => usage != null && usage!.chatRemaining <= 0;
  IncludeFlags get flags => include ?? includeAll;
  ConversationOut? get active => conversations.where((c) => c.id == activeId).firstOrNull;

  CoachState copyWith({
    bool? loaded,
    CoachUsageOut? Function()? usage,
    List<ConversationOut>? conversations,
    int? Function()? activeId,
    List<ChatMessageOut>? messages,
    String? Function()? pending,
    IncludeFlags? include,
    CoachLookbackDays? lookback,
    List<String>? attached,
    bool? loadingChat,
    String? Function()? error,
    ({String text})? Function()? draft,
    int? openRequests,
  }) => CoachState(
    loaded: loaded ?? this.loaded,
    usage: usage == null ? this.usage : usage(),
    conversations: conversations ?? this.conversations,
    activeId: activeId == null ? this.activeId : activeId(),
    messages: messages ?? this.messages,
    pending: pending == null ? this.pending : pending(),
    include: include ?? this.include,
    lookback: lookback ?? this.lookback,
    attached: attached ?? this.attached,
    loadingChat: loadingChat ?? this.loadingChat,
    error: error == null ? this.error : error(),
    draft: draft == null ? this.draft : draft(),
    openRequests: openRequests ?? this.openRequests,
  );
}

/// How long to wait before each resend of a message whose reply did not
/// arrive. About two minutes in all: past that, a Gemini call is not coming
/// back. Overridden with zeros in tests.
final coachRetryDelaysProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ],
);

/// A fresh id for one message. 128 random bits as hex: the server only
/// needs it to be unique and a safe document id.
String newClientMessageId([Random? random]) {
  final r = random ?? Random.secure();
  return [for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

/// Whether a failed send is worth sending again under the same id: the
/// request never got an answer (a timeout, a dropped connection), or the
/// server is still answering the first copy (409). Anything else is an
/// answer, and resending would get the same one.
bool isResendable(Object error) {
  if (error is! DioException) return false;
  final status = error.response?.statusCode;
  if (status != null) return status == 409;
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError ||
    DioExceptionType.unknown => true,
    _ => false,
  };
}

final coachProvider = NotifierProvider<CoachController, CoachState>(CoachController.new);

class CoachController extends Notifier<CoachState> {
  @override
  CoachState build() => const CoachState();

  CoachApi get _api => ref.read(apiProvider).getCoachApi();

  /// Read the budget and the chat list the first time the tab is shown,
  /// then resume the chat last used — the head of the list. Every reply
  /// carries the budget after this, so it is not re-read on a happy path.
  Future<void> ensureLoaded() async {
    if (state.loaded) return;
    state = state.copyWith(loaded: true);
    unawaited(_rereadUsage());
    try {
      final list = (await _api.listConversations()).data!;
      state = state.copyWith(conversations: list);
      // Only if nothing has been started meanwhile.
      if (list.isNotEmpty && state.activeId == null && state.messages.isEmpty && !state.sending) {
        await open(list.first.id, keepAttached: true);
      }
    } catch (_) {
      // The picker stays empty; a new chat still works.
    }
  }

  Future<void> _rereadUsage() async {
    try {
      final usage = (await _api.getCoachUsage()).data!;
      state = state.copyWith(usage: () => usage);
    } catch (_) {}
  }

  /// Open a stored chat: its turns, and the settings it is held at.
  ///
  /// `keepAttached` is for the resume on first load: a workout pinned from a
  /// session sheet before the tab was ever opened joins the resumed chat's
  /// own pins rather than being replaced by them (the web app lost it).
  Future<void> open(int id, {bool keepAttached = false}) async {
    final pinned = keepAttached ? state.attached : const <String>[];
    state = state.copyWith(loadingChat: true, error: () => null);
    try {
      final detail = (await _api.getConversation(conversationId: id)).data!;
      var attached = detail.sessionIds;
      for (final extra in pinned) {
        attached = attached.contains(extra) ? attached : toggleAttached(attached, extra);
      }
      state = state.copyWith(
        activeId: () => detail.id,
        messages: detail.messages,
        include: detail.include,
        lookback: detail.lookbackDays,
        attached: attached,
      );
    } catch (e) {
      state = state.copyWith(error: () => describeError(e));
    } finally {
      state = state.copyWith(loadingChat: false);
    }
  }

  /// Start a fresh chat. Nothing is written until the first message.
  void newChat() {
    state = state.copyWith(
      activeId: () => null,
      messages: const [],
      error: () => null,
      include: includeAll,
      lookback: coachDefaultLookback,
      attached: const [],
    );
  }

  Future<void> remove(int id) async {
    final previous = state.conversations;
    state = state.copyWith(conversations: removeById(previous, id));
    if (id == state.activeId) newChat();
    try {
      await _api.deleteConversation(conversationId: id);
    } catch (e) {
      state = state.copyWith(conversations: previous, error: () => describeError(e));
    }
  }

  void setInclude(IncludeFlags include) => state = state.copyWith(include: include);
  void setLookback(CoachLookbackDays days) => state = state.copyWith(lookback: days);
  void toggleWorkout(String id) => state = state.copyWith(attached: toggleAttached(state.attached, id));

  /// "Ask the coach about this session": pin it and ask the shell to open
  /// the tab. Idempotent — a session already pinned is not toggled off from
  /// a screen that gives no sign it was ever on.
  void pinFromSession(String sessionId) {
    final attached = state.attached.contains(sessionId) ? state.attached : toggleAttached(state.attached, sessionId);
    state = state.copyWith(attached: attached, openRequests: state.openRequests + 1);
  }

  /// Send one message and wait for the coach's reply.
  Future<void> send(String input) async {
    final text = input.trim();
    if (text.isEmpty || state.sending || state.exhausted) return;
    state = state.copyWith(pending: () => text, error: () => null, draft: () => null);

    final request = ChatRequest(
      content: text,
      conversationId: state.activeId,
      include: state.flags,
      lookbackDays: state.lookback,
      sessionIds: state.attached,
      clientMessageId: newClientMessageId(),
    );
    final delays = ref.read(coachRetryDelaysProvider);
    try {
      for (var attempt = 0; ; attempt++) {
        try {
          final turn = (await _api.sendCoachMessage(chatRequest: request, extra: slowRequest)).data!;
          state = state.copyWith(
            pending: () => null,
            messages: [...state.messages, turn.message, turn.reply],
            activeId: () => turn.conversation.id,
            conversations: promote(state.conversations, turn.conversation),
            usage: () => turn.usage,
          );
          return;
        } catch (e) {
          if (attempt >= delays.length || !isResendable(e)) rethrow;
          await Future<void>.delayed(delays[attempt]);
        }
      }
    } catch (e) {
      // Nothing was stored, so the question comes back off the transcript
      // and into the composer. The slot may have been spent even so, and a
      // 429 means the count moved without us: re-read it rather than guess.
      state = state.copyWith(pending: () => null, error: () => describeError(e), draft: () => (text: text));
      unawaited(_rereadUsage());
    }
  }
}

/// The sessions the attachment picker offers: deeper than the Fitness tab's
/// list, and only fetched once the picker or a pinned chip needs it, then
/// kept — the picker is opened repeatedly while assembling a question.
final attachableSessionsProvider = FutureProvider<List<ExerciseSessionOut>>(
  (ref) async => (await ref.read(apiProvider).getHealthApi().listExercises(limit: coachAttachPickerLimit)).data!,
);
