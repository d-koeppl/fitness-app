// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatRequest _$ChatRequestFromJson(Map<String, dynamic> json) => $checkedCreate(
  'ChatRequest',
  json,
  ($checkedConvert) {
    $checkKeys(json, requiredKeys: const ['content']);
    final val = ChatRequest(
      clientMessageId: $checkedConvert(
        'client_message_id',
        (v) => v as String?,
      ),
      content: $checkedConvert('content', (v) => v as String),
      conversationId: $checkedConvert(
        'conversation_id',
        (v) => (v as num?)?.toInt(),
      ),
      include: $checkedConvert(
        'include',
        (v) =>
            v == null ? null : IncludeFlags.fromJson(v as Map<String, dynamic>),
      ),
      lookbackDays: $checkedConvert(
        'lookback_days',
        (v) => $enumDecodeNullable(
          _$CoachLookbackDaysEnumMap,
          v,
          unknownValue: CoachLookbackDays.unknownDefaultOpenApi,
        ),
      ),
      sessionIds: $checkedConvert(
        'session_ids',
        (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'clientMessageId': 'client_message_id',
    'conversationId': 'conversation_id',
    'lookbackDays': 'lookback_days',
    'sessionIds': 'session_ids',
  },
);

Map<String, dynamic> _$ChatRequestToJson(ChatRequest instance) =>
    <String, dynamic>{
      'client_message_id': ?instance.clientMessageId,
      'content': instance.content,
      'conversation_id': ?instance.conversationId,
      'include': ?instance.include?.toJson(),
      'lookback_days': ?_$CoachLookbackDaysEnumMap[instance.lookbackDays],
      'session_ids': ?instance.sessionIds,
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
