//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/coach_lookback_days.dart';
import 'package:fitness_api/src/model/include_flags.dart';
import 'package:fitness_api/src/model/chat_message_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'conversation_detail_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ConversationDetailOut {
  /// Returns a new [ConversationDetailOut] instance.
  ConversationDetailOut({
    required this.createdAt,

    required this.id,

    required this.include,

    required this.lookbackDays,

    required this.messageCount,

    required this.messages,

    required this.sessionIds,

    required this.title,

    required this.updatedAt,
  });

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final int id;

  @JsonKey(name: r'include', required: true, includeIfNull: false)
  final IncludeFlags include;

  @JsonKey(
    name: r'lookback_days',
    required: true,
    includeIfNull: false,
    unknownEnumValue: CoachLookbackDays.unknownDefaultOpenApi,
  )
  final CoachLookbackDays lookbackDays;

  @JsonKey(name: r'message_count', required: true, includeIfNull: false)
  final int messageCount;

  @JsonKey(name: r'messages', required: true, includeIfNull: false)
  final List<ChatMessageOut> messages;

  @JsonKey(name: r'session_ids', required: true, includeIfNull: false)
  final List<String> sessionIds;

  @JsonKey(name: r'title', required: true, includeIfNull: false)
  final String title;

  @JsonKey(name: r'updated_at', required: true, includeIfNull: false)
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationDetailOut &&
          other.createdAt == createdAt &&
          other.id == id &&
          other.include == include &&
          other.lookbackDays == lookbackDays &&
          other.messageCount == messageCount &&
          other.messages == messages &&
          other.sessionIds == sessionIds &&
          other.title == title &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      createdAt.hashCode +
      id.hashCode +
      include.hashCode +
      lookbackDays.hashCode +
      messageCount.hashCode +
      messages.hashCode +
      sessionIds.hashCode +
      title.hashCode +
      updatedAt.hashCode;

  factory ConversationDetailOut.fromJson(Map<String, dynamic> json) =>
      _$ConversationDetailOutFromJson(json);

  Map<String, dynamic> toJson() => _$ConversationDetailOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
