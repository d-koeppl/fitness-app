// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_report_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AiReportOut _$AiReportOutFromJson(Map<String, dynamic> json) => $checkedCreate(
  'AiReportOut',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'created_at',
        'id',
        'insights',
        'model',
        'period_end',
        'period_start',
        'prompt_version',
        'summary_md',
        'tokens_used',
        'trigger',
      ],
    );
    final val = AiReportOut(
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      insights: $checkedConvert(
        'insights',
        (v) =>
            (v as Map<String, dynamic>).map((k, e) => MapEntry(k, e as Object)),
      ),
      model: $checkedConvert('model', (v) => v as String),
      periodEnd: $checkedConvert(
        'period_end',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      periodStart: $checkedConvert(
        'period_start',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      promptVersion: $checkedConvert('prompt_version', (v) => v as String),
      summaryMd: $checkedConvert('summary_md', (v) => v as String),
      tokensUsed: $checkedConvert('tokens_used', (v) => (v as num?)?.toInt()),
      trigger: $checkedConvert('trigger', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'createdAt': 'created_at',
    'periodEnd': 'period_end',
    'periodStart': 'period_start',
    'promptVersion': 'prompt_version',
    'summaryMd': 'summary_md',
    'tokensUsed': 'tokens_used',
  },
);

Map<String, dynamic> _$AiReportOutToJson(AiReportOut instance) =>
    <String, dynamic>{
      'created_at': instance.createdAt.toIso8601String(),
      'id': instance.id,
      'insights': instance.insights,
      'model': instance.model,
      'period_end': instance.periodEnd?.toIso8601String(),
      'period_start': instance.periodStart?.toIso8601String(),
      'prompt_version': instance.promptVersion,
      'summary_md': instance.summaryMd,
      'tokens_used': instance.tokensUsed,
      'trigger': instance.trigger,
    };
