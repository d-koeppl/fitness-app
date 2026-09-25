// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'refresh_report_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RefreshReportOut _$RefreshReportOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RefreshReportOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['report', 'sources']);
      final val = RefreshReportOut(
        report: $checkedConvert(
          'report',
          (v) => AiReportOut.fromJson(v as Map<String, dynamic>),
        ),
        sources: $checkedConvert(
          'sources',
          (v) => Map<String, String>.from(v as Map),
        ),
      );
      return val;
    });

Map<String, dynamic> _$RefreshReportOutToJson(RefreshReportOut instance) =>
    <String, dynamic>{
      'report': instance.report.toJson(),
      'sources': instance.sources,
    };
