// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drink_counter_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DrinkCounterOut _$DrinkCounterOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'DrinkCounterOut',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'alcohol_grams',
            'count',
            'first_logged_at',
            'last_logged_at',
            'volume_l',
          ],
        );
        final val = DrinkCounterOut(
          alcoholGrams: $checkedConvert(
            'alcohol_grams',
            (v) => (v as num).toInt(),
          ),
          count: $checkedConvert('count', (v) => (v as num).toInt()),
          firstLoggedAt: $checkedConvert(
            'first_logged_at',
            (v) => v == null ? null : DateTime.parse(v as String),
          ),
          lastLoggedAt: $checkedConvert(
            'last_logged_at',
            (v) => v == null ? null : DateTime.parse(v as String),
          ),
          volumeL: $checkedConvert('volume_l', (v) => v as num),
        );
        return val;
      },
      fieldKeyMap: const {
        'alcoholGrams': 'alcohol_grams',
        'firstLoggedAt': 'first_logged_at',
        'lastLoggedAt': 'last_logged_at',
        'volumeL': 'volume_l',
      },
    );

Map<String, dynamic> _$DrinkCounterOutToJson(DrinkCounterOut instance) =>
    <String, dynamic>{
      'alcohol_grams': instance.alcoholGrams,
      'count': instance.count,
      'first_logged_at': instance.firstLoggedAt?.toIso8601String(),
      'last_logged_at': instance.lastLoggedAt?.toIso8601String(),
      'volume_l': instance.volumeL,
    };
