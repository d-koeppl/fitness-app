//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'match_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class MatchOut {
  /// Returns a new [MatchOut] instance.
  MatchOut({
    required this.goals,

    required this.homeAway,

    required this.id,

    required this.matchDate,

    required this.minutesPlayed,

    required this.oefbGameId,

    required this.opponent,

    required this.redCard,

    required this.result,

    required this.started,

    required this.yellowCard,
  });

  @JsonKey(name: r'goals', required: true, includeIfNull: false)
  final int goals;

  @JsonKey(name: r'home_away', required: true, includeIfNull: false)
  final String homeAway;

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final int id;

  @JsonKey(name: r'match_date', required: true, includeIfNull: true)
  final DateTime? matchDate;

  @JsonKey(name: r'minutes_played', required: true, includeIfNull: false)
  final int minutesPlayed;

  @JsonKey(name: r'oefb_game_id', required: true, includeIfNull: false)
  final String oefbGameId;

  @JsonKey(name: r'opponent', required: true, includeIfNull: false)
  final String opponent;

  @JsonKey(name: r'red_card', required: true, includeIfNull: false)
  final bool redCard;

  @JsonKey(name: r'result', required: true, includeIfNull: true)
  final String? result;

  @JsonKey(name: r'started', required: true, includeIfNull: false)
  final bool started;

  @JsonKey(name: r'yellow_card', required: true, includeIfNull: false)
  final bool yellowCard;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchOut &&
          other.goals == goals &&
          other.homeAway == homeAway &&
          other.id == id &&
          other.matchDate == matchDate &&
          other.minutesPlayed == minutesPlayed &&
          other.oefbGameId == oefbGameId &&
          other.opponent == opponent &&
          other.redCard == redCard &&
          other.result == result &&
          other.started == started &&
          other.yellowCard == yellowCard;

  @override
  int get hashCode =>
      goals.hashCode +
      homeAway.hashCode +
      id.hashCode +
      (matchDate == null ? 0 : matchDate.hashCode) +
      minutesPlayed.hashCode +
      oefbGameId.hashCode +
      opponent.hashCode +
      redCard.hashCode +
      (result == null ? 0 : result.hashCode) +
      started.hashCode +
      yellowCard.hashCode;

  factory MatchOut.fromJson(Map<String, dynamic> json) =>
      _$MatchOutFromJson(json);

  Map<String, dynamic> toJson() => _$MatchOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
