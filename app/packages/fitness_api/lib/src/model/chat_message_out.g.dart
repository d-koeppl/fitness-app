// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatMessageOut _$ChatMessageOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ChatMessageOut', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['content', 'created_at', 'id', 'role'],
      );
      final val = ChatMessageOut(
        content: $checkedConvert('content', (v) => v as String),
        createdAt: $checkedConvert(
          'created_at',
          (v) => DateTime.parse(v as String),
        ),
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        role: $checkedConvert('role', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'createdAt': 'created_at'});

Map<String, dynamic> _$ChatMessageOutToJson(ChatMessageOut instance) =>
    <String, dynamic>{
      'content': instance.content,
      'created_at': instance.createdAt.toIso8601String(),
      'id': instance.id,
      'role': instance.role,
    };
