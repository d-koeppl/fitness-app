//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/ai_report_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'refresh_report_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class RefreshReportOut {
  /// Returns a new [RefreshReportOut] instance.
  RefreshReportOut({required this.report, required this.sources});

  @JsonKey(name: r'report', required: true, includeIfNull: false)
  final AiReportOut report;

  @JsonKey(name: r'sources', required: true, includeIfNull: false)
  final Map<String, String> sources;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RefreshReportOut &&
          other.report == report &&
          other.sources == sources;

  @override
  int get hashCode => report.hashCode + sources.hashCode;

  factory RefreshReportOut.fromJson(Map<String, dynamic> json) =>
      _$RefreshReportOutFromJson(json);

  Map<String, dynamic> toJson() => _$RefreshReportOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
