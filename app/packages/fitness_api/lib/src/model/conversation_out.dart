//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'conversation_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ConversationOut {
  /// Returns a new [ConversationOut] instance.
  ConversationOut({
    required this.createdAt,

    required this.id,

    required this.messageCount,

    required this.title,

    required this.updatedAt,
  });

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final int id;

  @JsonKey(name: r'message_count', required: true, includeIfNull: false)
  final int messageCount;

  @JsonKey(name: r'title', required: true, includeIfNull: false)
  final String title;

  @JsonKey(name: r'updated_at', required: true, includeIfNull: false)
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationOut &&
          other.createdAt == createdAt &&
          other.id == id &&
          other.messageCount == messageCount &&
          other.title == title &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      createdAt.hashCode +
      id.hashCode +
      messageCount.hashCode +
      title.hashCode +
      updatedAt.hashCode;

  factory ConversationOut.fromJson(Map<String, dynamic> json) =>
      _$ConversationOutFromJson(json);

  Map<String, dynamic> toJson() => _$ConversationOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
