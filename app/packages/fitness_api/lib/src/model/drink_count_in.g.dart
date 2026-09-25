// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drink_count_in.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DrinkCountIn _$DrinkCountInFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DrinkCountIn', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['count']);
      final val = DrinkCountIn(
        count: $checkedConvert('count', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$DrinkCountInToJson(DrinkCountIn instance) =>
    <String, dynamic>{'count': instance.count};
