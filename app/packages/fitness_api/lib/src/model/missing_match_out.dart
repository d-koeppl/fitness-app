//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'missing_match_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class MissingMatchOut {
  /// Returns a new [MissingMatchOut] instance.
  MissingMatchOut({
    required this.day,

    required this.kickoff,

    required this.title,
  });

  @JsonKey(name: r'day', required: true, includeIfNull: false)
  final DateTime day;

  @JsonKey(name: r'kickoff', required: true, includeIfNull: false)
  final DateTime kickoff;

  @JsonKey(name: r'title', required: true, includeIfNull: false)
  final String title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MissingMatchOut &&
          other.day == day &&
          other.kickoff == kickoff &&
          other.title == title;

  @override
  int get hashCode => day.hashCode + kickoff.hashCode + title.hashCode;

  factory MissingMatchOut.fromJson(Map<String, dynamic> json) =>
      _$MissingMatchOutFromJson(json);

  Map<String, dynamic> toJson() => _$MissingMatchOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
