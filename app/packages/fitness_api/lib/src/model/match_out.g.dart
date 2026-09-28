// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MatchOut _$MatchOutFromJson(Map<String, dynamic> json) => $checkedCreate(
  'MatchOut',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'goals',
        'home_away',
        'id',
        'match_date',
        'minutes_played',
        'oefb_game_id',
        'opponent',
        'red_card',
        'result',
        'session_id',
        'started',
        'yellow_card',
      ],
    );
    final val = MatchOut(
      goals: $checkedConvert('goals', (v) => (v as num).toInt()),
      homeAway: $checkedConvert('home_away', (v) => v as String),
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      matchDate: $checkedConvert(
        'match_date',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      minutesPlayed: $checkedConvert(
        'minutes_played',
        (v) => (v as num).toInt(),
      ),
      oefbGameId: $checkedConvert('oefb_game_id', (v) => v as String),
      opponent: $checkedConvert('opponent', (v) => v as String),
      redCard: $checkedConvert('red_card', (v) => v as bool),
      result: $checkedConvert('result', (v) => v as String?),
      sessionId: $checkedConvert('session_id', (v) => v as String?),
      started: $checkedConvert('started', (v) => v as bool),
      yellowCard: $checkedConvert('yellow_card', (v) => v as bool),
    );
    return val;
  },
  fieldKeyMap: const {
    'homeAway': 'home_away',
    'matchDate': 'match_date',
    'minutesPlayed': 'minutes_played',
    'oefbGameId': 'oefb_game_id',
    'redCard': 'red_card',
    'sessionId': 'session_id',
    'yellowCard': 'yellow_card',
  },
);

Map<String, dynamic> _$MatchOutToJson(MatchOut instance) => <String, dynamic>{
  'goals': instance.goals,
  'home_away': instance.homeAway,
  'id': instance.id,
  'match_date': instance.matchDate?.toIso8601String(),
  'minutes_played': instance.minutesPlayed,
  'oefb_game_id': instance.oefbGameId,
  'opponent': instance.opponent,
  'red_card': instance.redCard,
  'result': instance.result,
  'session_id': instance.sessionId,
  'started': instance.started,
  'yellow_card': instance.yellowCard,
};
