// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'league_table_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LeagueTableOut _$LeagueTableOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('LeagueTableOut', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['day', 'fetched_at', 'league', 'rows'],
      );
      final val = LeagueTableOut(
        day: $checkedConvert('day', (v) => DateTime.parse(v as String)),
        fetchedAt: $checkedConvert(
          'fetched_at',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        league: $checkedConvert('league', (v) => v as String),
        rows: $checkedConvert(
          'rows',
          (v) => (v as List<dynamic>)
              .map((e) => LeagueRowOut.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    }, fieldKeyMap: const {'fetchedAt': 'fetched_at'});

Map<String, dynamic> _$LeagueTableOutToJson(LeagueTableOut instance) =>
    <String, dynamic>{
      'day': instance.day.toIso8601String(),
      'fetched_at': instance.fetchedAt?.toIso8601String(),
      'league': instance.league,
      'rows': instance.rows.map((e) => e.toJson()).toList(),
    };
