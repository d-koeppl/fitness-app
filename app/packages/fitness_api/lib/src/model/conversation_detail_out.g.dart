// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_detail_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConversationDetailOut _$ConversationDetailOutFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'ConversationDetailOut',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'created_at',
        'id',
        'include',
        'lookback_days',
        'message_count',
        'messages',
        'session_ids',
        'title',
        'updated_at',
      ],
    );
    final val = ConversationDetailOut(
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      include: $checkedConvert(
        'include',
        (v) => IncludeFlags.fromJson(v as Map<String, dynamic>),
      ),
      lookbackDays: $checkedConvert(
        'lookback_days',
        (v) => $enumDecode(
          _$CoachLookbackDaysEnumMap,
          v,
          unknownValue: CoachLookbackDays.unknownDefaultOpenApi,
        ),
      ),
      messageCount: $checkedConvert('message_count', (v) => (v as num).toInt()),
      messages: $checkedConvert(
        'messages',
        (v) => (v as List<dynamic>)
            .map((e) => ChatMessageOut.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      sessionIds: $checkedConvert(
        'session_ids',
        (v) => (v as List<dynamic>).map((e) => e as String).toList(),
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
    'lookbackDays': 'lookback_days',
    'messageCount': 'message_count',
    'sessionIds': 'session_ids',
    'updatedAt': 'updated_at',
  },
);

Map<String, dynamic> _$ConversationDetailOutToJson(
  ConversationDetailOut instance,
) => <String, dynamic>{
  'created_at': instance.createdAt.toIso8601String(),
  'id': instance.id,
  'include': instance.include.toJson(),
  'lookback_days': _$CoachLookbackDaysEnumMap[instance.lookbackDays]!,
  'message_count': instance.messageCount,
  'messages': instance.messages.map((e) => e.toJson()).toList(),
  'session_ids': instance.sessionIds,
  'title': instance.title,
  'updated_at': instance.updatedAt.toIso8601String(),
};

const _$CoachLookbackDaysEnumMap = {
  CoachLookbackDays.number14: 14,
  CoachLookbackDays.number30: 30,
  CoachLookbackDays.number90: 90,
  CoachLookbackDays.number182: 182,
  CoachLookbackDays.number365: 365,
  CoachLookbackDays.number730: 730,
  CoachLookbackDays.unknownDefaultOpenApi: 11184809,
};
