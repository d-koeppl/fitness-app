// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_usage_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModelUsageOut _$ModelUsageOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ModelUsageOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['limit', 'model', 'used']);
      final val = ModelUsageOut(
        limit: $checkedConvert('limit', (v) => (v as num).toInt()),
        model: $checkedConvert('model', (v) => v as String),
        used: $checkedConvert('used', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$ModelUsageOutToJson(ModelUsageOut instance) =>
    <String, dynamic>{
      'limit': instance.limit,
      'model': instance.model,
      'used': instance.used,
    };
