// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'include_flags.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IncludeFlags _$IncludeFlagsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('IncludeFlags', json, ($checkedConvert) {
      final val = IncludeFlags(
        alcohol: $checkedConvert('alcohol', (v) => v as bool? ?? true),
        events: $checkedConvert('events', (v) => v as bool? ?? true),
        exercises: $checkedConvert('exercises', (v) => v as bool? ?? true),
        health: $checkedConvert('health', (v) => v as bool? ?? true),
        matches: $checkedConvert('matches', (v) => v as bool? ?? true),
        report: $checkedConvert('report', (v) => v as bool? ?? true),
      );
      return val;
    });

Map<String, dynamic> _$IncludeFlagsToJson(IncludeFlags instance) =>
    <String, dynamic>{
      'alcohol': ?instance.alcohol,
      'events': ?instance.events,
      'exercises': ?instance.exercises,
      'health': ?instance.health,
      'matches': ?instance.matches,
      'report': ?instance.report,
    };
