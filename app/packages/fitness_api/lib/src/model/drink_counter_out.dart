//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'drink_counter_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DrinkCounterOut {
  /// Returns a new [DrinkCounterOut] instance.
  DrinkCounterOut({
    required this.alcoholGrams,

    required this.count,

    required this.firstLoggedAt,

    required this.lastLoggedAt,

    required this.volumeL,
  });

  @JsonKey(name: r'alcohol_grams', required: true, includeIfNull: false)
  final int alcoholGrams;

  @JsonKey(name: r'count', required: true, includeIfNull: false)
  final int count;

  @JsonKey(name: r'first_logged_at', required: true, includeIfNull: true)
  final DateTime? firstLoggedAt;

  @JsonKey(name: r'last_logged_at', required: true, includeIfNull: true)
  final DateTime? lastLoggedAt;

  @JsonKey(name: r'volume_l', required: true, includeIfNull: false)
  final num volumeL;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrinkCounterOut &&
          other.alcoholGrams == alcoholGrams &&
          other.count == count &&
          other.firstLoggedAt == firstLoggedAt &&
          other.lastLoggedAt == lastLoggedAt &&
          other.volumeL == volumeL;

  @override
  int get hashCode =>
      alcoholGrams.hashCode +
      count.hashCode +
      (firstLoggedAt == null ? 0 : firstLoggedAt.hashCode) +
      (lastLoggedAt == null ? 0 : lastLoggedAt.hashCode) +
      volumeL.hashCode;

  factory DrinkCounterOut.fromJson(Map<String, dynamic> json) =>
      _$DrinkCounterOutFromJson(json);

  Map<String, dynamic> toJson() => _$DrinkCounterOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
