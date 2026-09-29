// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fixture_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FixtureOut _$FixtureOutFromJson(Map<String, dynamic> json) => $checkedCreate(
  'FixtureOut',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'art',
        'home_away',
        'kickoff',
        'oefb_game_id',
        'opponent',
        'opponent_standing',
      ],
    );
    final val = FixtureOut(
      art: $checkedConvert('art', (v) => v as String?),
      homeAway: $checkedConvert('home_away', (v) => v as String),
      kickoff: $checkedConvert(
        'kickoff',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      oefbGameId: $checkedConvert('oefb_game_id', (v) => v as String),
      opponent: $checkedConvert('opponent', (v) => v as String),
      opponentStanding: $checkedConvert(
        'opponent_standing',
        (v) => v == null
            ? null
            : OpponentStandingOut.fromJson(v as Map<String, dynamic>),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'homeAway': 'home_away',
    'oefbGameId': 'oefb_game_id',
    'opponentStanding': 'opponent_standing',
  },
);

Map<String, dynamic> _$FixtureOutToJson(FixtureOut instance) =>
    <String, dynamic>{
      'art': instance.art,
      'home_away': instance.homeAway,
      'kickoff': instance.kickoff?.toIso8601String(),
      'oefb_game_id': instance.oefbGameId,
      'opponent': instance.opponent,
      'opponent_standing': instance.opponentStanding?.toJson(),
    };
