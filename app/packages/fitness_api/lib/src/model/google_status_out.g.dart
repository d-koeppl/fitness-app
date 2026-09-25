// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'google_status_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GoogleStatusOut _$GoogleStatusOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GoogleStatusOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['calendar', 'health']);
      final val = GoogleStatusOut(
        calendar: $checkedConvert(
          'calendar',
          (v) => TokenStatusOut.fromJson(v as Map<String, dynamic>),
        ),
        health: $checkedConvert(
          'health',
          (v) => TokenStatusOut.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$GoogleStatusOutToJson(GoogleStatusOut instance) =>
    <String, dynamic>{
      'calendar': instance.calendar.toJson(),
      'health': instance.health.toJson(),
    };
