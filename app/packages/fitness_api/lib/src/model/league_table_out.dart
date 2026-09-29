//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/league_row_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'league_table_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LeagueTableOut {
  /// Returns a new [LeagueTableOut] instance.
  LeagueTableOut({
    required this.day,

    required this.fetchedAt,

    required this.league,

    required this.rows,
  });

  @JsonKey(name: r'day', required: true, includeIfNull: false)
  final DateTime day;

  @JsonKey(name: r'fetched_at', required: true, includeIfNull: true)
  final DateTime? fetchedAt;

  @JsonKey(name: r'league', required: true, includeIfNull: false)
  final String league;

  @JsonKey(name: r'rows', required: true, includeIfNull: false)
  final List<LeagueRowOut> rows;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeagueTableOut &&
          other.day == day &&
          other.fetchedAt == fetchedAt &&
          other.league == league &&
          other.rows == rows;

  @override
  int get hashCode =>
      day.hashCode +
      (fetchedAt == null ? 0 : fetchedAt.hashCode) +
      league.hashCode +
      rows.hashCode;

  factory LeagueTableOut.fromJson(Map<String, dynamic> json) =>
      _$LeagueTableOutFromJson(json);

  Map<String, dynamic> toJson() => _$LeagueTableOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
