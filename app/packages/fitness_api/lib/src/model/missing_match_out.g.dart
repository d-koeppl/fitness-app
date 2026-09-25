// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'missing_match_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MissingMatchOut _$MissingMatchOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('MissingMatchOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['day', 'kickoff', 'title']);
      final val = MissingMatchOut(
        day: $checkedConvert('day', (v) => DateTime.parse(v as String)),
        kickoff: $checkedConvert('kickoff', (v) => DateTime.parse(v as String)),
        title: $checkedConvert('title', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$MissingMatchOutToJson(MissingMatchOut instance) =>
    <String, dynamic>{
      'day': instance.day.toIso8601String(),
      'kickoff': instance.kickoff.toIso8601String(),
      'title': instance.title,
    };
