import 'package:flutter/foundation.dart';

/// Un programme d'entraînement du compte, réduit à ce qu'il faut pour le
/// choisir dans une liste — même principe que `RouteSummary` : le
/// [shareToken] est la seule clé nécessaire pour le résoudre ensuite en
/// [TrainingProgram] complet (voir `fetchSharedTrainingProgram`).
@immutable
class TrainingProgramSummary {
  const TrainingProgramSummary({
    required this.id,
    required this.name,
    required this.shareToken,
    this.durationSeconds = 0,
    this.segmentCount = 0,
  });

  final int id;
  final String name;
  final String shareToken;
  final int durationSeconds;
  final int segmentCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'share_token': shareToken,
        'duration_seconds': durationSeconds,
        'segment_count': segmentCount,
      };

  /// Décode une entrée de `/api/training_programs`. Tolérant comme
  /// `RouteSummary.fromJson` : ce qui manque vaut zéro, seuls le nom et le
  /// jeton — sans quoi la ligne serait inchoisissable ou inouvrable — font
  /// rendre `null`.
  static TrainingProgramSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final name = raw['name'];
    final token = raw['share_token'];
    if (name is! String || name.isEmpty) return null;
    if (token is! String || token.isEmpty) return null;

    return TrainingProgramSummary(
      id: raw['id'] is num ? (raw['id'] as num).toInt() : 0,
      name: name,
      shareToken: token,
      durationSeconds: raw['duration_seconds'] is num ? (raw['duration_seconds'] as num).toInt() : 0,
      segmentCount: raw['segment_count'] is num ? (raw['segment_count'] as num).toInt() : 0,
    );
  }

  /// Décode `{ training_programs: [...] }`.
  static List<TrainingProgramSummary> listFromPayload(Object? raw) {
    final programs = raw is Map ? raw['training_programs'] : raw;
    if (programs is! List) return const [];

    return [
      for (final entry in programs)
        if (TrainingProgramSummary.fromJson(entry) case final program?) program,
    ];
  }
}
