// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drink_day_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DrinkDayOut _$DrinkDayOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DrinkDayOut', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['count', 'date', 'editable', 'reported'],
      );
      final val = DrinkDayOut(
        count: $checkedConvert('count', (v) => (v as num).toInt()),
        date: $checkedConvert('date', (v) => DateTime.parse(v as String)),
        editable: $checkedConvert('editable', (v) => v as bool),
        reported: $checkedConvert('reported', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$DrinkDayOutToJson(DrinkDayOut instance) =>
    <String, dynamic>{
      'count': instance.count,
      'date': instance.date.toIso8601String(),
      'editable': instance.editable,
      'reported': instance.reported,
    };
