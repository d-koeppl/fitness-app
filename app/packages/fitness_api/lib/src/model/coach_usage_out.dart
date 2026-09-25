//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/model_usage_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'coach_usage_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CoachUsageOut {
  /// Returns a new [CoachUsageOut] instance.
  CoachUsageOut({
    required this.chatRemaining,

    required this.limit,

    required this.models,

    required this.resetsAt,

    required this.used,
  });

  @JsonKey(name: r'chat_remaining', required: true, includeIfNull: false)
  final int chatRemaining;

  @JsonKey(name: r'limit', required: true, includeIfNull: false)
  final int limit;

  @JsonKey(name: r'models', required: true, includeIfNull: false)
  final List<ModelUsageOut> models;

  @JsonKey(name: r'resets_at', required: true, includeIfNull: false)
  final DateTime resetsAt;

  @JsonKey(name: r'used', required: true, includeIfNull: false)
  final int used;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoachUsageOut &&
          other.chatRemaining == chatRemaining &&
          other.limit == limit &&
          other.models == models &&
          other.resetsAt == resetsAt &&
          other.used == used;

  @override
  int get hashCode =>
      chatRemaining.hashCode +
      limit.hashCode +
      models.hashCode +
      resetsAt.hashCode +
      used.hashCode;

  factory CoachUsageOut.fromJson(Map<String, dynamic> json) =>
      _$CoachUsageOutFromJson(json);

  Map<String, dynamic> toJson() => _$CoachUsageOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
