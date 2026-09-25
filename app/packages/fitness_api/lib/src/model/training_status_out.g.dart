// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'training_status_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TrainingStatusOut _$TrainingStatusOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'TrainingStatusOut',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'days_of_history',
            'fatigue',
            'fitness',
            'form',
            'form_pct',
            'headline',
            'notes',
            'ramp_pct',
            'readiness',
            'readiness_parts',
            'recovery',
            'recovery_parts',
            'scores',
            'series',
            'status',
          ],
        );
        final val = TrainingStatusOut(
          daysOfHistory: $checkedConvert(
            'days_of_history',
            (v) => (v as num).toInt(),
          ),
          fatigue: $checkedConvert('fatigue', (v) => v as num),
          fitness: $checkedConvert('fitness', (v) => v as num),
          form: $checkedConvert('form', (v) => v as num),
          formPct: $checkedConvert('form_pct', (v) => v as num),
          headline: $checkedConvert('headline', (v) => v as String),
          notes: $checkedConvert(
            'notes',
            (v) => (v as List<dynamic>).map((e) => e as String).toList(),
          ),
          rampPct: $checkedConvert('ramp_pct', (v) => v as num),
          readiness: $checkedConvert('readiness', (v) => (v as num?)?.toInt()),
          readinessParts: $checkedConvert(
            'readiness_parts',
            (v) => Map<String, num>.from(v as Map),
          ),
          recovery: $checkedConvert('recovery', (v) => (v as num?)?.toInt()),
          recoveryParts: $checkedConvert(
            'recovery_parts',
            (v) => Map<String, num>.from(v as Map),
          ),
          scores: $checkedConvert(
            'scores',
            (v) => (v as List<dynamic>)
                .map((e) => ScorePointOut.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
          series: $checkedConvert(
            'series',
            (v) => (v as List<dynamic>)
                .map((e) => DayPointOut.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
          status: $checkedConvert('status', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {
        'daysOfHistory': 'days_of_history',
        'formPct': 'form_pct',
        'rampPct': 'ramp_pct',
        'readinessParts': 'readiness_parts',
        'recoveryParts': 'recovery_parts',
      },
    );

Map<String, dynamic> _$TrainingStatusOutToJson(TrainingStatusOut instance) =>
    <String, dynamic>{
      'days_of_history': instance.daysOfHistory,
      'fatigue': instance.fatigue,
      'fitness': instance.fitness,
      'form': instance.form,
      'form_pct': instance.formPct,
      'headline': instance.headline,
      'notes': instance.notes,
      'ramp_pct': instance.rampPct,
      'readiness': instance.readiness,
      'readiness_parts': instance.readinessParts,
      'recovery': instance.recovery,
      'recovery_parts': instance.recoveryParts,
      'scores': instance.scores.map((e) => e.toJson()).toList(),
      'series': instance.series.map((e) => e.toJson()).toList(),
      'status': instance.status,
    };
