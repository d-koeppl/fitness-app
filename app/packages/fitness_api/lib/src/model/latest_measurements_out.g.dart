// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'latest_measurements_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LatestMeasurementsOut _$LatestMeasurementsOutFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('LatestMeasurementsOut', json, ($checkedConvert) {
  final val = LatestMeasurementsOut(
    vo2max: $checkedConvert(
      'vo2max',
      (v) =>
          v == null ? null : MeasurementOut.fromJson(v as Map<String, dynamic>),
    ),
    weightKg: $checkedConvert(
      'weight_kg',
      (v) =>
          v == null ? null : MeasurementOut.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
}, fieldKeyMap: const {'weightKg': 'weight_kg'});

Map<String, dynamic> _$LatestMeasurementsOutToJson(
  LatestMeasurementsOut instance,
) => <String, dynamic>{
  'vo2max': ?instance.vo2max?.toJson(),
  'weight_kg': ?instance.weightKg?.toJson(),
};
