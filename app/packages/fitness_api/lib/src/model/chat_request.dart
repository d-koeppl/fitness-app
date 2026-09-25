//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/coach_lookback_days.dart';
import 'package:fitness_api/src/model/include_flags.dart';
import 'package:json_annotation/json_annotation.dart';

part 'chat_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ChatRequest {
  /// Returns a new [ChatRequest] instance.
  ChatRequest({
    this.clientMessageId,

    required this.content,

    this.conversationId,

    this.include,

    this.lookbackDays,

    this.sessionIds,
  });

  @JsonKey(name: r'client_message_id', required: false, includeIfNull: false)
  final String? clientMessageId;

  @JsonKey(name: r'content', required: true, includeIfNull: false)
  final String content;

  @JsonKey(name: r'conversation_id', required: false, includeIfNull: false)
  final int? conversationId;

  @JsonKey(name: r'include', required: false, includeIfNull: false)
  final IncludeFlags? include;

  @JsonKey(
    name: r'lookback_days',
    required: false,
    includeIfNull: false,
    unknownEnumValue: CoachLookbackDays.unknownDefaultOpenApi,
  )
  final CoachLookbackDays? lookbackDays;

  @JsonKey(name: r'session_ids', required: false, includeIfNull: false)
  final List<String>? sessionIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatRequest &&
          other.clientMessageId == clientMessageId &&
          other.content == content &&
          other.conversationId == conversationId &&
          other.include == include &&
          other.lookbackDays == lookbackDays &&
          other.sessionIds == sessionIds;

  @override
  int get hashCode =>
      clientMessageId.hashCode +
      content.hashCode +
      conversationId.hashCode +
      include.hashCode +
      lookbackDays.hashCode +
      sessionIds.hashCode;

  factory ChatRequest.fromJson(Map<String, dynamic> json) =>
      _$ChatRequestFromJson(json);

  Map<String, dynamic> toJson() => _$ChatRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
