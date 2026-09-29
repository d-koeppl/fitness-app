// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'league_row_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LeagueRowOut _$LeagueRowOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'LeagueRowOut',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'drawn',
            'goal_difference',
            'goals_against',
            'goals_for',
            'is_us',
            'lost',
            'played',
            'points',
            'rank',
            'rank_change',
            'team',
            'won',
          ],
        );
        final val = LeagueRowOut(
          drawn: $checkedConvert('drawn', (v) => (v as num).toInt()),
          goalDifference: $checkedConvert(
            'goal_difference',
            (v) => (v as num).toInt(),
          ),
          goalsAgainst: $checkedConvert(
            'goals_against',
            (v) => (v as num).toInt(),
          ),
          goalsFor: $checkedConvert('goals_for', (v) => (v as num).toInt()),
          isUs: $checkedConvert('is_us', (v) => v as bool),
          lost: $checkedConvert('lost', (v) => (v as num).toInt()),
          played: $checkedConvert('played', (v) => (v as num).toInt()),
          points: $checkedConvert('points', (v) => (v as num).toInt()),
          rank: $checkedConvert('rank', (v) => (v as num).toInt()),
          rankChange: $checkedConvert('rank_change', (v) => (v as num).toInt()),
          team: $checkedConvert('team', (v) => v as String),
          won: $checkedConvert('won', (v) => (v as num).toInt()),
        );
        return val;
      },
      fieldKeyMap: const {
        'goalDifference': 'goal_difference',
        'goalsAgainst': 'goals_against',
        'goalsFor': 'goals_for',
        'isUs': 'is_us',
        'rankChange': 'rank_change',
      },
    );

Map<String, dynamic> _$LeagueRowOutToJson(LeagueRowOut instance) =>
    <String, dynamic>{
      'drawn': instance.drawn,
      'goal_difference': instance.goalDifference,
      'goals_against': instance.goalsAgainst,
      'goals_for': instance.goalsFor,
      'is_us': instance.isUs,
      'lost': instance.lost,
      'played': instance.played,
      'points': instance.points,
      'rank': instance.rank,
      'rank_change': instance.rankChange,
      'team': instance.team,
      'won': instance.won,
    };
