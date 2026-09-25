// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConversationOut _$ConversationOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ConversationOut',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'created_at',
            'id',
            'message_count',
            'title',
            'updated_at',
          ],
        );
        final val = ConversationOut(
          createdAt: $checkedConvert(
            'created_at',
            (v) => DateTime.parse(v as String),
          ),
          id: $checkedConvert('id', (v) => (v as num).toInt()),
          messageCount: $checkedConvert(
            'message_count',
            (v) => (v as num).toInt(),
          ),
          title: $checkedConvert('title', (v) => v as String),
          updatedAt: $checkedConvert(
            'updated_at',
            (v) => DateTime.parse(v as String),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'createdAt': 'created_at',
        'messageCount': 'message_count',
        'updatedAt': 'updated_at',
      },
    );

Map<String, dynamic> _$ConversationOutToJson(ConversationOut instance) =>
    <String, dynamic>{
      'created_at': instance.createdAt.toIso8601String(),
      'id': instance.id,
      'message_count': instance.messageCount,
      'title': instance.title,
      'updated_at': instance.updatedAt.toIso8601String(),
    };
