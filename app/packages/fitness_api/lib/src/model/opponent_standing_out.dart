//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'opponent_standing_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class OpponentStandingOut {
  /// Returns a new [OpponentStandingOut] instance.
  OpponentStandingOut({
    required this.atKickoff,

    required this.goalDifference,

    required this.ourPoints,

    required this.ourPointsPerGame,

    required this.ourRank,

    required this.played,

    required this.points,

    required this.pointsGap,

    required this.pointsPerGame,

    required this.rank,

    required this.rankChange,

    required this.strength,

    required this.tableDay,
  });

  @JsonKey(name: r'at_kickoff', required: true, includeIfNull: false)
  final bool atKickoff;

  @JsonKey(name: r'goal_difference', required: true, includeIfNull: false)
  final int goalDifference;

  @JsonKey(name: r'our_points', required: true, includeIfNull: true)
  final int? ourPoints;

  @JsonKey(name: r'our_points_per_game', required: true, includeIfNull: true)
  final num? ourPointsPerGame;

  @JsonKey(name: r'our_rank', required: true, includeIfNull: true)
  final int? ourRank;

  @JsonKey(name: r'played', required: true, includeIfNull: false)
  final int played;

  @JsonKey(name: r'points', required: true, includeIfNull: false)
  final int points;

  @JsonKey(name: r'points_gap', required: true, includeIfNull: true)
  final int? pointsGap;

  @JsonKey(name: r'points_per_game', required: true, includeIfNull: true)
  final num? pointsPerGame;

  @JsonKey(name: r'rank', required: true, includeIfNull: false)
  final int rank;

  @JsonKey(name: r'rank_change', required: true, includeIfNull: false)
  final int rankChange;

  @JsonKey(name: r'strength', required: true, includeIfNull: true)
  final String? strength;

  @JsonKey(name: r'table_day', required: true, includeIfNull: false)
  final DateTime tableDay;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpponentStandingOut &&
          other.atKickoff == atKickoff &&
          other.goalDifference == goalDifference &&
          other.ourPoints == ourPoints &&
          other.ourPointsPerGame == ourPointsPerGame &&
          other.ourRank == ourRank &&
          other.played == played &&
          other.points == points &&
          other.pointsGap == pointsGap &&
          other.pointsPerGame == pointsPerGame &&
          other.rank == rank &&
          other.rankChange == rankChange &&
          other.strength == strength &&
          other.tableDay == tableDay;

  @override
  int get hashCode =>
      atKickoff.hashCode +
      goalDifference.hashCode +
      (ourPoints == null ? 0 : ourPoints.hashCode) +
      (ourPointsPerGame == null ? 0 : ourPointsPerGame.hashCode) +
      (ourRank == null ? 0 : ourRank.hashCode) +
      played.hashCode +
      points.hashCode +
      (pointsGap == null ? 0 : pointsGap.hashCode) +
      (pointsPerGame == null ? 0 : pointsPerGame.hashCode) +
      rank.hashCode +
      rankChange.hashCode +
      (strength == null ? 0 : strength.hashCode) +
      tableDay.hashCode;

  factory OpponentStandingOut.fromJson(Map<String, dynamic> json) =>
      _$OpponentStandingOutFromJson(json);

  Map<String, dynamic> toJson() => _$OpponentStandingOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
