//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/opponent_standing_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'fixture_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FixtureOut {
  /// Returns a new [FixtureOut] instance.
  FixtureOut({
    required this.art,

    required this.homeAway,

    required this.kickoff,

    required this.oefbGameId,

    required this.opponent,

    required this.opponentStanding,
  });

  @JsonKey(name: r'art', required: true, includeIfNull: true)
  final String? art;

  @JsonKey(name: r'home_away', required: true, includeIfNull: false)
  final String homeAway;

  @JsonKey(name: r'kickoff', required: true, includeIfNull: true)
  final DateTime? kickoff;

  @JsonKey(name: r'oefb_game_id', required: true, includeIfNull: false)
  final String oefbGameId;

  @JsonKey(name: r'opponent', required: true, includeIfNull: false)
  final String opponent;

  @JsonKey(name: r'opponent_standing', required: true, includeIfNull: true)
  final OpponentStandingOut? opponentStanding;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FixtureOut &&
          other.art == art &&
          other.homeAway == homeAway &&
          other.kickoff == kickoff &&
          other.oefbGameId == oefbGameId &&
          other.opponent == opponent &&
          other.opponentStanding == opponentStanding;

  @override
  int get hashCode =>
      (art == null ? 0 : art.hashCode) +
      homeAway.hashCode +
      (kickoff == null ? 0 : kickoff.hashCode) +
      oefbGameId.hashCode +
      opponent.hashCode +
      (opponentStanding == null ? 0 : opponentStanding.hashCode);

  factory FixtureOut.fromJson(Map<String, dynamic> json) =>
      _$FixtureOutFromJson(json);

  Map<String, dynamic> toJson() => _$FixtureOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
