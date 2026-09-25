// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_event_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CalendarEventOut _$CalendarEventOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CalendarEventOut',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'all_day',
            'end_ts',
            'id',
            'location',
            'start_ts',
            'title',
          ],
        );
        final val = CalendarEventOut(
          allDay: $checkedConvert('all_day', (v) => v as bool),
          endTs: $checkedConvert(
            'end_ts',
            (v) => v == null ? null : DateTime.parse(v as String),
          ),
          id: $checkedConvert('id', (v) => v as String),
          location: $checkedConvert('location', (v) => v as String?),
          startTs: $checkedConvert(
            'start_ts',
            (v) => v == null ? null : DateTime.parse(v as String),
          ),
          title: $checkedConvert('title', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {
        'allDay': 'all_day',
        'endTs': 'end_ts',
        'startTs': 'start_ts',
      },
    );

Map<String, dynamic> _$CalendarEventOutToJson(CalendarEventOut instance) =>
    <String, dynamic>{
      'all_day': instance.allDay,
      'end_ts': instance.endTs?.toIso8601String(),
      'id': instance.id,
      'location': instance.location,
      'start_ts': instance.startTs?.toIso8601String(),
      'title': instance.title,
    };
