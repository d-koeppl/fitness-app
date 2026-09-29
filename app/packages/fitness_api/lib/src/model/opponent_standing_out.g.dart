// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'opponent_standing_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OpponentStandingOut _$OpponentStandingOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'OpponentStandingOut',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'at_kickoff',
            'goal_difference',
            'our_points',
            'our_points_per_game',
            'our_rank',
            'played',
            'points',
            'points_gap',
            'points_per_game',
            'rank',
            'rank_change',
            'strength',
            'table_day',
          ],
        );
        final val = OpponentStandingOut(
          atKickoff: $checkedConvert('at_kickoff', (v) => v as bool),
          goalDifference: $checkedConvert(
            'goal_difference',
            (v) => (v as num).toInt(),
          ),
          ourPoints: $checkedConvert('our_points', (v) => (v as num?)?.toInt()),
          ourPointsPerGame: $checkedConvert(
            'our_points_per_game',
            (v) => v as num?,
          ),
          ourRank: $checkedConvert('our_rank', (v) => (v as num?)?.toInt()),
          played: $checkedConvert('played', (v) => (v as num).toInt()),
          points: $checkedConvert('points', (v) => (v as num).toInt()),
          pointsGap: $checkedConvert('points_gap', (v) => (v as num?)?.toInt()),
          pointsPerGame: $checkedConvert('points_per_game', (v) => v as num?),
          rank: $checkedConvert('rank', (v) => (v as num).toInt()),
          rankChange: $checkedConvert('rank_change', (v) => (v as num).toInt()),
          strength: $checkedConvert('strength', (v) => v as String?),
          tableDay: $checkedConvert(
            'table_day',
            (v) => DateTime.parse(v as String),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'atKickoff': 'at_kickoff',
        'goalDifference': 'goal_difference',
        'ourPoints': 'our_points',
        'ourPointsPerGame': 'our_points_per_game',
        'ourRank': 'our_rank',
        'pointsGap': 'points_gap',
        'pointsPerGame': 'points_per_game',
        'rankChange': 'rank_change',
        'tableDay': 'table_day',
      },
    );

Map<String, dynamic> _$OpponentStandingOutToJson(
  OpponentStandingOut instance,
) => <String, dynamic>{
  'at_kickoff': instance.atKickoff,
  'goal_difference': instance.goalDifference,
  'our_points': instance.ourPoints,
  'our_points_per_game': instance.ourPointsPerGame,
  'our_rank': instance.ourRank,
  'played': instance.played,
  'points': instance.points,
  'points_gap': instance.pointsGap,
  'points_per_game': instance.pointsPerGame,
  'rank': instance.rank,
  'rank_change': instance.rankChange,
  'strength': instance.strength,
  'table_day': instance.tableDay.toIso8601String(),
};
