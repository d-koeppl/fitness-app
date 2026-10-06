// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'check_in_in.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CheckInIn _$CheckInInFromJson(Map<String, dynamic> json) =>
    $checkedCreate('CheckInIn', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['feeling', 'strength']);
      final val = CheckInIn(
        feeling: $checkedConvert(
          'feeling',
          (v) => $enumDecode(
            _$CheckInInFeelingEnumEnumMap,
            v,
            unknownValue: CheckInInFeelingEnum.unknownDefaultOpenApi,
          ),
        ),
        note: $checkedConvert('note', (v) => v as String?),
        strength: $checkedConvert('strength', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$CheckInInToJson(CheckInIn instance) => <String, dynamic>{
  'feeling': _$CheckInInFeelingEnumEnumMap[instance.feeling]!,
  'note': ?instance.note,
  'strength': instance.strength,
};

const _$CheckInInFeelingEnumEnumMap = {
  CheckInInFeelingEnum.energised: 'energised',
  CheckInInFeelingEnum.good: 'good',
  CheckInInFeelingEnum.okay: 'okay',
  CheckInInFeelingEnum.tired: 'tired',
  CheckInInFeelingEnum.stressed: 'stressed',
  CheckInInFeelingEnum.sore: 'sore',
  CheckInInFeelingEnum.ill: 'ill',
  CheckInInFeelingEnum.cold: 'cold',
  CheckInInFeelingEnum.other: 'other',
  CheckInInFeelingEnum.unknownDefaultOpenApi: 'unknown_default_open_api',
};
