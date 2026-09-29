//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'league_row_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LeagueRowOut {
  /// Returns a new [LeagueRowOut] instance.
  LeagueRowOut({
    required this.drawn,

    required this.goalDifference,

    required this.goalsAgainst,

    required this.goalsFor,

    required this.isUs,

    required this.lost,

    required this.played,

    required this.points,

    required this.rank,

    required this.rankChange,

    required this.team,

    required this.won,
  });

  @JsonKey(name: r'drawn', required: true, includeIfNull: false)
  final int drawn;

  @JsonKey(name: r'goal_difference', required: true, includeIfNull: false)
  final int goalDifference;

  @JsonKey(name: r'goals_against', required: true, includeIfNull: false)
  final int goalsAgainst;

  @JsonKey(name: r'goals_for', required: true, includeIfNull: false)
  final int goalsFor;

  @JsonKey(name: r'is_us', required: true, includeIfNull: false)
  final bool isUs;

  @JsonKey(name: r'lost', required: true, includeIfNull: false)
  final int lost;

  @JsonKey(name: r'played', required: true, includeIfNull: false)
  final int played;

  @JsonKey(name: r'points', required: true, includeIfNull: false)
  final int points;

  @JsonKey(name: r'rank', required: true, includeIfNull: false)
  final int rank;

  @JsonKey(name: r'rank_change', required: true, includeIfNull: false)
  final int rankChange;

  @JsonKey(name: r'team', required: true, includeIfNull: false)
  final String team;

  @JsonKey(name: r'won', required: true, includeIfNull: false)
  final int won;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeagueRowOut &&
          other.drawn == drawn &&
          other.goalDifference == goalDifference &&
          other.goalsAgainst == goalsAgainst &&
          other.goalsFor == goalsFor &&
          other.isUs == isUs &&
          other.lost == lost &&
          other.played == played &&
          other.points == points &&
          other.rank == rank &&
          other.rankChange == rankChange &&
          other.team == team &&
          other.won == won;

  @override
  int get hashCode =>
      drawn.hashCode +
      goalDifference.hashCode +
      goalsAgainst.hashCode +
      goalsFor.hashCode +
      isUs.hashCode +
      lost.hashCode +
      played.hashCode +
      points.hashCode +
      rank.hashCode +
      rankChange.hashCode +
      team.hashCode +
      won.hashCode;

  factory LeagueRowOut.fromJson(Map<String, dynamic> json) =>
      _$LeagueRowOutFromJson(json);

  Map<String, dynamic> toJson() => _$LeagueRowOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
