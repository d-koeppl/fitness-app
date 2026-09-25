//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'ai_report_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AiReportOut {
  /// Returns a new [AiReportOut] instance.
  AiReportOut({
    required this.createdAt,

    required this.id,

    required this.insights,

    required this.model,

    required this.periodEnd,

    required this.periodStart,

    required this.promptVersion,

    required this.summaryMd,

    required this.tokensUsed,

    required this.trigger,
  });

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final int id;

  @JsonKey(name: r'insights', required: true, includeIfNull: false)
  final Map<String, Object> insights;

  @JsonKey(name: r'model', required: true, includeIfNull: false)
  final String model;

  @JsonKey(name: r'period_end', required: true, includeIfNull: true)
  final DateTime? periodEnd;

  @JsonKey(name: r'period_start', required: true, includeIfNull: true)
  final DateTime? periodStart;

  @JsonKey(name: r'prompt_version', required: true, includeIfNull: false)
  final String promptVersion;

  @JsonKey(name: r'summary_md', required: true, includeIfNull: false)
  final String summaryMd;

  @JsonKey(name: r'tokens_used', required: true, includeIfNull: true)
  final int? tokensUsed;

  @JsonKey(name: r'trigger', required: true, includeIfNull: false)
  final String trigger;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiReportOut &&
          other.createdAt == createdAt &&
          other.id == id &&
          other.insights == insights &&
          other.model == model &&
          other.periodEnd == periodEnd &&
          other.periodStart == periodStart &&
          other.promptVersion == promptVersion &&
          other.summaryMd == summaryMd &&
          other.tokensUsed == tokensUsed &&
          other.trigger == trigger;

  @override
  int get hashCode =>
      createdAt.hashCode +
      id.hashCode +
      insights.hashCode +
      model.hashCode +
      (periodEnd == null ? 0 : periodEnd.hashCode) +
      (periodStart == null ? 0 : periodStart.hashCode) +
      promptVersion.hashCode +
      summaryMd.hashCode +
      (tokensUsed == null ? 0 : tokensUsed.hashCode) +
      trigger.hashCode;

  factory AiReportOut.fromJson(Map<String, dynamic> json) =>
      _$AiReportOutFromJson(json);

  Map<String, dynamic> toJson() => _$AiReportOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
