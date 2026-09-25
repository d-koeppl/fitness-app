// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coach_usage_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CoachUsageOut _$CoachUsageOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CoachUsageOut',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'chat_remaining',
            'limit',
            'models',
            'resets_at',
            'used',
          ],
        );
        final val = CoachUsageOut(
          chatRemaining: $checkedConvert(
            'chat_remaining',
            (v) => (v as num).toInt(),
          ),
          limit: $checkedConvert('limit', (v) => (v as num).toInt()),
          models: $checkedConvert(
            'models',
            (v) => (v as List<dynamic>)
                .map((e) => ModelUsageOut.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
          resetsAt: $checkedConvert(
            'resets_at',
            (v) => DateTime.parse(v as String),
          ),
          used: $checkedConvert('used', (v) => (v as num).toInt()),
        );
        return val;
      },
      fieldKeyMap: const {
        'chatRemaining': 'chat_remaining',
        'resetsAt': 'resets_at',
      },
    );

Map<String, dynamic> _$CoachUsageOutToJson(CoachUsageOut instance) =>
    <String, dynamic>{
      'chat_remaining': instance.chatRemaining,
      'limit': instance.limit,
      'models': instance.models.map((e) => e.toJson()).toList(),
      'resets_at': instance.resetsAt.toIso8601String(),
      'used': instance.used,
    };
