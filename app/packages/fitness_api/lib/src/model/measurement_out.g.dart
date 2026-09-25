// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'measurement_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MeasurementOut _$MeasurementOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('MeasurementOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['date', 'value']);
      final val = MeasurementOut(
        date: $checkedConvert('date', (v) => DateTime.parse(v as String)),
        value: $checkedConvert('value', (v) => v as num),
      );
      return val;
    });

Map<String, dynamic> _$MeasurementOutToJson(MeasurementOut instance) =>
    <String, dynamic>{
      'date': instance.date.toIso8601String(),
      'value': instance.value,
    };
