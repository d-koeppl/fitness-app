//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/day_point_out.dart';
import 'package:fitness_api/src/model/score_point_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'training_status_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class TrainingStatusOut {
  /// Returns a new [TrainingStatusOut] instance.
  TrainingStatusOut({
    required this.daysOfHistory,

    required this.fatigue,

    required this.fitness,

    required this.form,

    required this.formPct,

    required this.headline,

    required this.notes,

    required this.rampPct,

    required this.readiness,

    required this.readinessParts,

    required this.recovery,

    required this.recoveryParts,

    required this.scores,

    required this.series,

    required this.status,
  });

  @JsonKey(name: r'days_of_history', required: true, includeIfNull: false)
  final int daysOfHistory;

  @JsonKey(name: r'fatigue', required: true, includeIfNull: false)
  final num fatigue;

  @JsonKey(name: r'fitness', required: true, includeIfNull: false)
  final num fitness;

  @JsonKey(name: r'form', required: true, includeIfNull: false)
  final num form;

  @JsonKey(name: r'form_pct', required: true, includeIfNull: false)
  final num formPct;

  @JsonKey(name: r'headline', required: true, includeIfNull: false)
  final String headline;

  @JsonKey(name: r'notes', required: true, includeIfNull: false)
  final List<String> notes;

  @JsonKey(name: r'ramp_pct', required: true, includeIfNull: false)
  final num rampPct;

  @JsonKey(name: r'readiness', required: true, includeIfNull: true)
  final int? readiness;

  @JsonKey(name: r'readiness_parts', required: true, includeIfNull: false)
  final Map<String, num> readinessParts;

  @JsonKey(name: r'recovery', required: true, includeIfNull: true)
  final int? recovery;

  @JsonKey(name: r'recovery_parts', required: true, includeIfNull: false)
  final Map<String, num> recoveryParts;

  @JsonKey(name: r'scores', required: true, includeIfNull: false)
  final List<ScorePointOut> scores;

  @JsonKey(name: r'series', required: true, includeIfNull: false)
  final List<DayPointOut> series;

  @JsonKey(name: r'status', required: true, includeIfNull: false)
  final String status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainingStatusOut &&
          other.daysOfHistory == daysOfHistory &&
          other.fatigue == fatigue &&
          other.fitness == fitness &&
          other.form == form &&
          other.formPct == formPct &&
          other.headline == headline &&
          other.notes == notes &&
          other.rampPct == rampPct &&
          other.readiness == readiness &&
          other.readinessParts == readinessParts &&
          other.recovery == recovery &&
          other.recoveryParts == recoveryParts &&
          other.scores == scores &&
          other.series == series &&
          other.status == status;

  @override
  int get hashCode =>
      daysOfHistory.hashCode +
      fatigue.hashCode +
      fitness.hashCode +
      form.hashCode +
      formPct.hashCode +
      headline.hashCode +
      notes.hashCode +
      rampPct.hashCode +
      (readiness == null ? 0 : readiness.hashCode) +
      readinessParts.hashCode +
      (recovery == null ? 0 : recovery.hashCode) +
      recoveryParts.hashCode +
      scores.hashCode +
      series.hashCode +
      status.hashCode;

  factory TrainingStatusOut.fromJson(Map<String, dynamic> json) =>
      _$TrainingStatusOutFromJson(json);

  Map<String, dynamic> toJson() => _$TrainingStatusOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
