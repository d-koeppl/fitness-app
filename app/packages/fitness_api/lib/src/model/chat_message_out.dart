//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'chat_message_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ChatMessageOut {
  /// Returns a new [ChatMessageOut] instance.
  ChatMessageOut({
    required this.content,

    required this.createdAt,

    required this.id,

    required this.role,
  });

  @JsonKey(name: r'content', required: true, includeIfNull: false)
  final String content;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final int id;

  @JsonKey(name: r'role', required: true, includeIfNull: false)
  final String role;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageOut &&
          other.content == content &&
          other.createdAt == createdAt &&
          other.id == id &&
          other.role == role;

  @override
  int get hashCode =>
      content.hashCode + createdAt.hashCode + id.hashCode + role.hashCode;

  factory ChatMessageOut.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageOutFromJson(json);

  Map<String, dynamic> toJson() => _$ChatMessageOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
