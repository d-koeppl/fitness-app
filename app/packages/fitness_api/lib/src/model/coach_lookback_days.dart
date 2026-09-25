//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

/// How far back the coach's health, workout and match data reaches, in days.
enum CoachLookbackDays {
  /// How far back the coach's health, workout and match data reaches, in days.
  @JsonValue(14)
  number14('14'),

  /// How far back the coach's health, workout and match data reaches, in days.
  @JsonValue(30)
  number30('30'),

  /// How far back the coach's health, workout and match data reaches, in days.
  @JsonValue(90)
  number90('90'),

  /// How far back the coach's health, workout and match data reaches, in days.
  @JsonValue(182)
  number182('182'),

  /// How far back the coach's health, workout and match data reaches, in days.
  @JsonValue(365)
  number365('365'),

  /// How far back the coach's health, workout and match data reaches, in days.
  @JsonValue(730)
  number730('730'),

  /// How far back the coach's health, workout and match data reaches, in days.
  @JsonValue(11184809)
  unknownDefaultOpenApi('11184809');

  const CoachLookbackDays(this.value);

  final String value;

  @override
  String toString() => value;
}
