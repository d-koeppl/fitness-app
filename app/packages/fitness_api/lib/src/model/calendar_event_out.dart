//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'calendar_event_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CalendarEventOut {
  /// Returns a new [CalendarEventOut] instance.
  CalendarEventOut({
    required this.allDay,

    required this.endTs,

    required this.id,

    required this.location,

    required this.startTs,

    required this.title,
  });

  @JsonKey(name: r'all_day', required: true, includeIfNull: false)
  final bool allDay;

  @JsonKey(name: r'end_ts', required: true, includeIfNull: true)
  final DateTime? endTs;

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'location', required: true, includeIfNull: true)
  final String? location;

  @JsonKey(name: r'start_ts', required: true, includeIfNull: true)
  final DateTime? startTs;

  @JsonKey(name: r'title', required: true, includeIfNull: true)
  final String? title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarEventOut &&
          other.allDay == allDay &&
          other.endTs == endTs &&
          other.id == id &&
          other.location == location &&
          other.startTs == startTs &&
          other.title == title;

  @override
  int get hashCode =>
      allDay.hashCode +
      (endTs == null ? 0 : endTs.hashCode) +
      id.hashCode +
      (location == null ? 0 : location.hashCode) +
      (startTs == null ? 0 : startTs.hashCode) +
      (title == null ? 0 : title.hashCode);

  factory CalendarEventOut.fromJson(Map<String, dynamic> json) =>
      _$CalendarEventOutFromJson(json);

  Map<String, dynamic> toJson() => _$CalendarEventOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
