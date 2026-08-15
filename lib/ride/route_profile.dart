import 'package:flutter/foundation.dart';

import '../recording/elevation_profile_point.dart';

/// Le profil d'altitude de tout le tracé en cours, reçu une fois par
/// (re)chargement (voir `companionRouteProfile`/`buildCompanionRouteProfile`
/// côté site) — même construction que [ClimbProfile] mais sur toute la
/// distance plutôt qu'un seul col, pour `AltitudeProfileCard`
/// (`lib/ride/blocks/altitude_profile_block.dart`).
@immutable
class RouteProfile {
  const RouteProfile({
    required this.totalDistM,
    required this.points,
    required this.segmentGrades,
  });

  final double totalDistM;

  /// Ordonnés par distance croissante. Contrairement à [ClimbProfile.points],
  /// peut être vide ou n'avoir qu'un point — un tracé retiré republie un
  /// profil vide (voir `unloadRoute`, `RouteNavigation.vue`) plutôt que de
  /// laisser le dernier profil affiché ; c'est au widget de décider de l'état
  /// de repli sur `points.length < 2`.
  final List<ElevationProfilePoint> points;

  /// Pente lissée de chaque segment — length == points.length - 1.
  final List<double> segmentGrades;

  bool get isUsable =>
      points.length >= 2 && segmentGrades.length == points.length - 1;

  static RouteProfile? fromJson(Object? raw) {
    if (raw is! Map || raw['type'] != 'route_profile') return null;
    final rawPoints = raw['points'];
    final rawGrades = raw['segmentGrades'];
    if (rawPoints is! List || rawGrades is! List) return null;

    final points = <ElevationProfilePoint>[];
    for (final p in rawPoints) {
      if (p is! Map) return null;
      final distM = _toDouble(p['distM']);
      final altM = _toDouble(p['altM']);
      if (distM == null || altM == null) return null;
      points.add(ElevationProfilePoint(distM: distM, altM: altM));
    }
    final grades = <double>[];
    for (final g in rawGrades) {
      final v = _toDouble(g);
      if (v == null) return null;
      grades.add(v);
    }

    return RouteProfile(
      totalDistM: _toDouble(raw['totalDistM']) ?? 0,
      points: points,
      segmentGrades: grades,
    );
  }
}

/// Le profil du tracé en cours, à écouter comme [ClimbProfileNotifier]. Sans
/// persistance : un tracé est une chose de la sortie, jamais quelque chose à
/// retrouver après un redémarrage de l'appli.
class RouteProfileNotifier extends ValueNotifier<RouteProfile?> {
  RouteProfileNotifier() : super(null);

  /// Range un message venu de la page. Un message illisible est ignoré : on
  /// garde le dernier profil valable plutôt que de vider l'écran. Contrairement
  /// à [ClimbProfileNotifier.accept], un profil vide (tracé retiré) EST accepté
  /// — [RouteProfile.fromJson] ne rejette pas `points.length < 2`, seul
  /// [RouteProfile.isUsable] le distingue à l'affichage.
  void accept(Map<dynamic, dynamic> json) {
    final next = RouteProfile.fromJson(json);
    if (next != null) value = next;
  }

  void reset() => value = null;
}

double? _toDouble(Object? raw) => raw is num ? raw.toDouble() : null;
