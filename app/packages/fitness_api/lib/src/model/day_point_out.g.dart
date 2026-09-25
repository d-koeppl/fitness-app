// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'day_point_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DayPointOut _$DayPointOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DayPointOut', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['date', 'fatigue', 'fitness', 'load'],
      );
      final val = DayPointOut(
        date: $checkedConvert('date', (v) => v as String),
        fatigue: $checkedConvert('fatigue', (v) => v as num),
        fitness: $checkedConvert('fitness', (v) => v as num),
        load: $checkedConvert('load', (v) => v as num),
      );
      return val;
    });

Map<String, dynamic> _$DayPointOutToJson(DayPointOut instance) =>
    <String, dynamic>{
      'date': instance.date,
      'fatigue': instance.fatigue,
      'fitness': instance.fitness,
      'load': instance.load,
    };
