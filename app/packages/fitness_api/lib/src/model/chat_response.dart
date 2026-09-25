//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/conversation_out.dart';
import 'package:fitness_api/src/model/coach_usage_out.dart';
import 'package:fitness_api/src/model/chat_message_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'chat_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ChatResponse {
  /// Returns a new [ChatResponse] instance.
  ChatResponse({
    required this.conversation,

    required this.message,

    required this.reply,

    required this.usage,
  });

  @JsonKey(name: r'conversation', required: true, includeIfNull: false)
  final ConversationOut conversation;

  @JsonKey(name: r'message', required: true, includeIfNull: false)
  final ChatMessageOut message;

  @JsonKey(name: r'reply', required: true, includeIfNull: false)
  final ChatMessageOut reply;

  @JsonKey(name: r'usage', required: true, includeIfNull: false)
  final CoachUsageOut usage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatResponse &&
          other.conversation == conversation &&
          other.message == message &&
          other.reply == reply &&
          other.usage == usage;

  @override
  int get hashCode =>
      conversation.hashCode +
      message.hashCode +
      reply.hashCode +
      usage.hashCode;

  factory ChatResponse.fromJson(Map<String, dynamic> json) =>
      _$ChatResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ChatResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
