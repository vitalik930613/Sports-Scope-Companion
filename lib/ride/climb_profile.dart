import 'package:flutter/foundation.dart';

/// Un point du profil d'un col : distance depuis le départ du col, altitude.
@immutable
class ClimbProfilePoint {
  const ClimbProfilePoint({required this.distM, required this.altM});
  final double distM;
  final double altM;
}

/// Le profil gradué d'un col, reçu une fois par col (voir la doc de
/// [NavClimb] dans nav_state.dart : « il aura son propre message le jour où
/// on le dessinera » — c'est ce message).
///
/// Volontairement dépourvu de toute mise en forme (pas de chemin SVG, pas de
/// couleur) : c'est `gradeColorOf` (lib/ui/grade_colors.dart) qui colore
/// chaque segment, et cette classe qui calcule elle-même la mise à l'échelle
/// 0-100 — même division du travail que companionNav/NavState, où la page
/// envoie des mesures brutes et l'appli choisit sa mise en scène.
@immutable
class ClimbProfile {
  const ClimbProfile({
    required this.id,
    required this.gainM,
    required this.lengthM,
    required this.avgGrade,
    required this.category,
    required this.points,
    required this.segmentGrades,
  });

  /// Clé de dédoublonnage : l'index de départ du col côté site. Sert
  /// uniquement à comparer « même col reçu deux fois » — aucune signification
  /// hors de la session en cours.
  final int id;
  final double gainM;
  final double lengthM;
  final double avgGrade;
  final String? category;

  /// Ordonnés par distance croissante, au moins 2 points.
  final List<ClimbProfilePoint> points;

  /// Pente lissée de chaque segment [points[i], points[i+1]] — length ==
  /// points.length - 1. Déjà lissée côté site (fenêtre par sport, réglable) :
  /// l'appli ne la recalcule jamais elle-même, elle se contente de la
  /// colorer (voir gradeColorOf).
  final List<double> segmentGrades;

  bool get isUsable =>
      points.length >= 2 && segmentGrades.length == points.length - 1;

  static ClimbProfile? fromJson(Object? raw) {
    if (raw is! Map || raw['type'] != 'climb_profile') return null;
    final id = raw['id'];
    final rawPoints = raw['points'];
    final rawGrades = raw['segmentGrades'];
    if (id is! num || rawPoints is! List || rawGrades is! List) return null;

    final points = <ClimbProfilePoint>[];
    for (final p in rawPoints) {
      if (p is! Map) return null;
      final distM = _toDouble(p['distM']);
      final altM = _toDouble(p['altM']);
      if (distM == null || altM == null) return null;
      points.add(ClimbProfilePoint(distM: distM, altM: altM));
    }
    final grades = <double>[];
    for (final g in rawGrades) {
      final v = _toDouble(g);
      if (v == null) return null;
      grades.add(v);
    }

    final profile = ClimbProfile(
      id: id.toInt(),
      gainM: _toDouble(raw['gainM']) ?? 0,
      lengthM: _toDouble(raw['lengthM']) ?? 0,
      avgGrade: _toDouble(raw['avgGrade']) ?? 0,
      category: raw['category'] is String ? raw['category'] as String : null,
      points: points,
      segmentGrades: grades,
    );
    return profile.isUsable ? profile : null;
  }
}

/// Le profil du col en cours, à écouter comme [NavStateNotifier]. Sans
/// persistance : un col est une chose de la sortie, jamais quelque chose à
/// retrouver après un redémarrage de l'appli.
class ClimbProfileNotifier extends ValueNotifier<ClimbProfile?> {
  ClimbProfileNotifier() : super(null);

  /// Range un message venu de la page. Un message illisible est ignoré : on
  /// garde le dernier profil valable plutôt que de vider l'écran.
  void accept(Map<dynamic, dynamic> json) {
    final next = ClimbProfile.fromJson(json);
    if (next != null) value = next;
  }

  void reset() => value = null;
}

double? _toDouble(Object? raw) => raw is num ? raw.toDouble() : null;
