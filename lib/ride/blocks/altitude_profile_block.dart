import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../recording/elevation_profile_point.dart';
import '../../recording/ride_recorder.dart';
import '../../ui/formats.dart';
import '../nav_state.dart';
import '../route_profile.dart';
import 'block_card.dart';
import 'elevation_profile_surface.dart';

/// Le profil d'altitude de toute la sortie, en graphique — voir
/// `AltitudeProfileBlock` (`dashboard/dashboard_block.dart`). Deux allures
/// selon le contexte, choisies ici et non dans l'éditeur :
///
/// - un tracé chargé et en cours ([routeProfile] exploitable, [nav] sur
///   trace) donne le profil du parcours entier, fait/restant — même dessin
///   que `ClimbProfileCard`, sur toute la distance — ou, si [windowKm] est
///   réglé, une fenêtre « roulante » des prochains kilomètres seulement (voir
///   [_rollingCard]) ;
/// - sinon, la sortie enregistrée (`recorder.elevationTrack`) donne le profil
///   de ce qui a été effectivement parcouru, sans portion « restante » —
///   [windowKm] n'y a aucun effet, il n'y a rien « à venir » à montrer sans
///   tracé.
///
/// **Contrairement à `ClimbProfileCard`, reste utile sans carte** : la
/// deuxième allure ne dépend d'aucune page web, seulement de
/// `RideRecorder.elevationTrack`, qui existe dès qu'on enregistre.
class AltitudeProfileCard extends StatelessWidget {
  const AltitudeProfileCard({
    super.key,
    required this.routeProfile,
    required this.nav,
    required this.recorder,
    this.windowKm,
    this.color,
    this.textColor,
  });

  final ValueListenable<RouteProfile?>? routeProfile;
  final ValueListenable<NavState?>? nav;
  final RideRecorder recorder;

  /// Largeur de la fenêtre roulante, en km — voir `AltitudeProfileBlock.windowKm`.
  final double? windowKm;

  final Color? color;
  final Color? textColor;

  static const _title = "Profil d'altitude";

  @override
  Widget build(BuildContext context) {
    final routeProfile = this.routeProfile;
    final nav = this.nav;

    return ListenableBuilder(
      listenable: Listenable.merge([
        recorder,
        if (routeProfile != null) routeProfile,
        if (nav != null) nav,
      ]),
      builder: (context, _) => _build(routeProfile, nav),
    );
  }

  Widget _build(
    ValueListenable<RouteProfile?>? routeProfile,
    ValueListenable<NavState?>? nav,
  ) {
    final navState = nav?.value;
    final profile = routeProfile?.value;
    if (navState != null && navState.onRoute && profile != null && profile.isUsable) {
      final ratio = _traveledRatio(profile, navState);
      if (ratio != null) return _routeCard(profile, ratio);
    }

    final trackPoints = recorder.elevationTrack.points;
    if (trackPoints.length >= 2) return _rideCard(trackPoints);

    return BlockCard(
      title: _title,
      lines: const ['En attente de position…'],
      color: color,
      textColor: textColor,
    );
  }

  Widget _routeCard(RouteProfile profile, double ratio) {
    final windowKm = this.windowKm;
    if (windowKm != null) return _rollingCard(profile, ratio, windowKm);

    final cursorIdx = _cursorIndex(profile.points, ratio * profile.totalDistM);
    final remainingGainM = _remainingGainM(profile.points, cursorIdx);
    final grade = _gradeNear(profile.segmentGrades, cursorIdx);
    return ElevationProfileSurface(
      title: _title,
      headline: '+${remainingGainM.round()} m',
      aside: formatDistance(profile.totalDistM * (1 - ratio)),
      grade: grade,
      points: profile.points,
      segmentGrades: profile.segmentGrades,
      ratio: ratio,
      color: color,
      textColor: textColor,
    );
  }

  /// La fenêtre roulante : au lieu du tracé entier, seuls les [windowKm]
  /// prochains kilomètres depuis la position courante — recadrés à l'origine
  /// ([_sliceProfile]) pour que le graphique remplisse toute sa largeur, comme
  /// s'il ne connaissait rien du tracé déjà parcouru. Le curseur et l'aire
  /// « déjà fait » n'ont plus lieu d'être : tout ce qui se dessine est « à
  /// venir » ([ElevationProfileSurface.ratio] à `null`, comme la sortie libre
  /// sans tracé).
  Widget _rollingCard(RouteProfile profile, double ratio, double windowKm) {
    final traveledM = ratio * profile.totalDistM;
    final endM = math.min(traveledM + windowKm * 1000, profile.totalDistM);
    final sliced = _sliceProfile(profile.points, profile.segmentGrades, traveledM, endM);

    if (sliced.points.length < 2) {
      return BlockCard(
        title: _title,
        lines: const ['Arrivée toute proche.'],
        color: color,
        textColor: textColor,
      );
    }

    final windowGainM = _remainingGainM(sliced.points, 0);
    final grade = _gradeNear(sliced.grades, 0);
    return ElevationProfileSurface(
      title: _title,
      headline: '+${windowGainM.round()} m',
      aside: formatDistance(endM - traveledM),
      grade: grade,
      points: sliced.points,
      segmentGrades: sliced.grades,
      ratio: null,
      color: color,
      textColor: textColor,
    );
  }

  /// Découpe [points]/[grades] à la fenêtre [startDistM]–[endDistM], en
  /// interpolant l'altitude aux deux bords plutôt que de sauter au point
  /// échantillonné le plus proche — sans ça, la fenêtre « saute » d'un
  /// échantillon à l'autre au lieu de glisser en continu à mesure qu'on
  /// avance. Un segment garde la pente que le site a déjà lissée
  /// ([RouteProfile.segmentGrades]) même rogné à ses bords : la pente d'un
  /// segment linéaire ne change pas si on le raccourcit. Distances rebasées à
  /// 0 : [ElevationProfileGraph] met à l'échelle sur `points.last.distM`, donc
  /// un premier point resté à son décalage d'origine laisserait la fenêtre ne
  /// remplir qu'une fraction de la largeur.
  ///
  /// Pure, non couverte par un test — voir la mémoire « pas de tests ».
  static ({List<ElevationProfilePoint> points, List<double> grades}) _sliceProfile(
    List<ElevationProfilePoint> points,
    List<double> grades,
    double startDistM,
    double endDistM,
  ) {
    final slicedPoints = <ElevationProfilePoint>[];
    final slicedGrades = <double>[];

    for (var i = 0; i < grades.length; i++) {
      final segStart = points[i];
      final segEnd = points[i + 1];
      if (segEnd.distM <= startDistM || segStart.distM >= endDistM) continue;

      final clippedStartM = math.max(segStart.distM, startDistM);
      final clippedEndM = math.min(segEnd.distM, endDistM);
      if (slicedPoints.isEmpty) {
        slicedPoints.add(_pointAt(segStart, segEnd, clippedStartM));
      }
      slicedPoints.add(_pointAt(segStart, segEnd, clippedEndM));
      slicedGrades.add(grades[i]);
    }

    return (
      points: [for (final p in slicedPoints) ElevationProfilePoint(distM: p.distM - startDistM, altM: p.altM)],
      grades: slicedGrades,
    );
  }

  static ElevationProfilePoint _pointAt(ElevationProfilePoint a, ElevationProfilePoint b, double distM) {
    final span = b.distM - a.distM;
    final t = span > 0 ? (distM - a.distM) / span : 0.0;
    return ElevationProfilePoint(distM: distM, altM: a.altM + t * (b.altM - a.altM));
  }

  Widget _rideCard(List<ElevationProfilePoint> trackPoints) {
    final stats = recorder.stats;
    return ElevationProfileSurface(
      title: _title,
      headline: '+${stats.ascentM.round()} m',
      aside: formatDistance(stats.distanceM),
      grade: stats.gradePercent ?? 0,
      points: trackPoints,
      segmentGrades: _localGrades(trackPoints),
      ratio: null,
      color: color,
      textColor: textColor,
    );
  }

  /// Même formule que `traveledDistM` (`route_climbs.dart`), mais rapportée à
  /// [RouteProfile.totalDistM] plutôt qu'à `RouteClimbs.totalDistM` — les deux
  /// valent la même chose sur un même tracé, mais ce composant ne doit pas
  /// dépendre de la présence de `routeClimbs` pour fonctionner.
  static double? _traveledRatio(RouteProfile profile, NavState nav) {
    if (nav.isStale(DateTime.now()) || profile.totalDistM <= 0) return null;
    final traveled = (profile.totalDistM - nav.remainingM).clamp(0.0, profile.totalDistM);
    return traveled / profile.totalDistM;
  }

  /// L'indice du dernier point du profil (déjà rééchantillonné, ~400 points
  /// pour tout le tracé) qui précède la distance donnée — assez précis pour un
  /// graphique de case, pas une mesure d'ingénieur.
  static int _cursorIndex(List<ElevationProfilePoint> points, double distM) {
    var idx = 0;
    for (var i = 0; i < points.length; i++) {
      if (points[i].distM > distM) break;
      idx = i;
    }
    return idx;
  }

  static double _remainingGainM(List<ElevationProfilePoint> points, int cursorIdx) {
    var gain = 0.0;
    for (var i = cursorIdx; i < points.length - 1; i++) {
      final delta = points[i + 1].altM - points[i].altM;
      if (delta > 0) gain += delta;
    }
    return gain;
  }

  static double _gradeNear(List<double> segmentGrades, int cursorIdx) {
    if (segmentGrades.isEmpty) return 0;
    return segmentGrades[cursorIdx.clamp(0, segmentGrades.length - 1)];
  }

  /// Pente de chaque segment consécutif de la trace accumulée — personne ne
  /// la transmet ici (contrairement au tracé, où le site l'a déjà lissée) :
  /// c'est le calcul local validé pour ce mode.
  static List<double> _localGrades(List<ElevationProfilePoint> points) {
    final grades = <double>[];
    for (var i = 0; i < points.length - 1; i++) {
      final dd = points[i + 1].distM - points[i].distM;
      grades.add(dd > 0 ? (points[i + 1].altM - points[i].altM) / dd * 100 : 0);
    }
    return grades;
  }
}
