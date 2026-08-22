import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../navigation/navigation_target.dart';
import 'fit_writer.dart';
import 'ride_session.dart';
import 'ride_stats.dart';
import 'track_point.dart';

/// Le JSON attendu par `POST /api/imported_activities` (dépôt Rails,
/// `ImportedActivitiesController#create`), construit directement depuis nos
/// propres points — sans repasser par un `.fit` qu'il faudrait ensuite faire
/// relire par `fit-file-parser` côté site. On a déjà tout ce que ce parseur en
/// extrairait pour un import « déposé à la main », et sous une forme plus
/// fidèle : le JSONL n'a pas la perte d'un aller-retour par un format binaire
/// qui n'a qu'un seul champ d'altitude ou pas de tours en parallèle.
///
/// La forme des flux (`streams`) et des tours (`laps`) suit celle que produit
/// `buildImportedActivityPayload` (`app/javascript/fitImport.ts`, dépôt
/// Rails) — c'est ce que la page de dépôt du site envoie déjà pour un `.fit`
/// glissé à la main. Toucher à cette forme demande de vérifier les deux
/// dépôts.
///
/// Ce que cette fonction ne fait *pas*, volontairement : ni `fillHoles` sur
/// l'altitude, ni `despike` sur la position, ni `grade_smooth`. Ces trois-là
/// existent côté site pour rattraper un `.fit` **étranger**, dont on ne
/// connaît pas l'appareil ; les nôtres sortent de notre propre GPS, déjà tel
/// quel sur le tableau de bord pendant la sortie, sans lissage de plus. Un
/// trou vaut mieux qu'une valeur inventée pour le combler.
///
/// Lève [EmptyRide] sur une sortie sans le moindre point, même garde qu'à
/// l'export.
Map<String, dynamic> buildRideUploadPayload({
  required RideSession session,
  required List<TrackPoint> points,
  required FitSport sport,
}) {
  if (points.isEmpty) throw const EmptyRide();

  final stats = RideStats.of(points);
  final start = points.first.at;
  final hasBaro = points.any((p) => p.baroAltitudeM != null);

  final time = <int>[];
  final distance = <double>[];
  final latlng = <List<double>?>[];
  final altitude = <double?>[];
  final velocity = <double?>[];
  final heartrate = <int?>[];
  final cadence = <int?>[];
  final watts = <int?>[];

  for (final point in points) {
    time.add(point.at.difference(start).inSeconds);
    distance.add(point.distanceM);
    latlng.add(point.hasPosition ? [point.lat!, point.lng!] : null);
    altitude.add(hasBaro ? point.baroAltitudeM : point.altitudeM);
    velocity.add(RideStats.speedOf(point));
    heartrate.add(point.heartRate);
    cadence.add(point.cadence?.round());
    watts.add(point.power);
  }

  final streams = <String, dynamic>{
    'time': {'data': time},
    'distance': {'data': distance},
  };
  // Même seuil de moitié que l'import `.fit` : une trace dont le GPS a manqué
  // la majorité des points ne vaut pas d'être dessinée.
  final positionCount = latlng.where((p) => p != null).length;
  if (positionCount >= 2 && positionCount >= latlng.length * 0.5) {
    streams['latlng'] = {'data': latlng};
  }
  if (altitude.any((v) => v != null)) {
    streams['altitude'] = {'data': altitude};
  }
  // Les trous sont remplacés par 0, jamais laissés `null` : c'est ce que le
  // site fait déjà pour un `.fit` déposé, et c'est sans risque côté zones —
  // `ZoneDistribution.histogram` écarte les valeurs nulles ou négatives.
  if (velocity.any((v) => v != null)) {
    streams['velocity_smooth'] = {'data': velocity.map((v) => v ?? 0).toList()};
  }
  if (heartrate.any((v) => v != null)) {
    streams['heartrate'] = {'data': heartrate.map((v) => v ?? 0).toList()};
  }
  if (cadence.any((v) => v != null)) {
    streams['cadence'] = {'data': cadence.map((v) => v ?? 0).toList()};
  }
  if (watts.any((v) => v != null)) {
    streams['watts'] = {'data': watts.map((v) => v ?? 0).toList()};
  }

  return {
    'source': 'fit',
    'filename': FitWriter.fileName(session),
    'name': '${sport.label} · ${_dateLabel(session.startedAt)}',
    'activity_type': _activityType(sport),
    'started_at': session.startedAt.toUtc().toIso8601String(),
    'distance_m': stats.distanceM,
    'moving_time_s': stats.movingTime.inSeconds,
    'elapsed_time_s': points.last.at.difference(start).inSeconds,
    'total_elevation_gain': stats.ascentM,
    'average_speed': stats.avgSpeedMps,
    'max_speed': stats.maxSpeedMps,
    'average_heartrate': stats.avgHeartRate,
    'max_heartrate': stats.maxHeartRate,
    'average_watts': stats.avgPower,
    'max_watts': stats.maxPower,
    'average_cadence': stats.avgCadence,
    'max_cadence': stats.maxCadence,
    if (stats.hasPosition) 'start_latlng': [stats.firstLat, stats.firstLng],
    if (stats.hasPosition) 'end_latlng': [stats.lastLat, stats.lastLng],
    'streams': streams,
    'laps': _lapsPayload(points),
  };
}

/// Vocabulaire Strava, repris par `routeSportFor` (`activityHelpers.ts`, dépôt
/// Rails) pour proposer le bon profil de routage si la sortie sert un jour à
/// créer un itinéraire — `mountainbike` et `hike` sont les sous-chaînes qu'il
/// reconnaît. Un export `.fit` classique ne peut pas faire mieux : le format
/// ne porte le VTT que dans `sub_sport`, un champ que `fit-file-parser` ne
/// remonte pas dans `session.sport`. Ici on choisit directement la chaîne,
/// donc autant choisir la bonne.
String _activityType(FitSport sport) => switch (sport) {
      FitSport.cycling => 'Ride',
      FitSport.mtb => 'MountainBikeRide',
      FitSport.hiking => 'Hike',
    };

String _dateLabel(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Les tours, à la forme Strava (indices dans les flux ci-dessus) qu'attend
/// `ImportedActivitiesController#create`. Mêmes bornes que celles écrites dans
/// le `.fit` (`lapGroupsOf`, `track_point.dart`) — jusqu'à la même sortie sans
/// tour manuel, qui donne ici aussi un unique tour couvrant toute la sortie.
List<Map<String, dynamic>> _lapsPayload(List<TrackPoint> points) {
  final groups = lapGroupsOf(points);
  final laps = <Map<String, dynamic>>[];
  var startIndex = 0;
  var lapBaselineM = 0.0;

  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    final endIndex = startIndex + group.length - 1;
    // Un tour d'un seul point ne couvre aucun intervalle : `clean_laps` côté
    // Rails l'écarterait de toute façon (`end_index <= start_index`).
    if (endIndex > startIndex) {
      final lapStats = RideStats.of(group);
      laps.add({
        'lap_index': i + 1,
        'start_index': startIndex,
        'end_index': endIndex,
        'elapsed_time': group.last.at.difference(group.first.at).inSeconds,
        'moving_time': lapStats.movingTime.inSeconds,
        'distance': group.last.distanceM - lapBaselineM,
      });
    }
    lapBaselineM = group.last.distanceM;
    startIndex = endIndex + 1;
  }
  return laps;
}

/// Comment s'est terminé un envoi.
enum RideUploadStatus {
  ok,

  /// Le site a répondu 401 : personne n'est connecté dans le pot de cookies.
  /// À dire tel quel — se connecter dans Compte suffit à corriger.
  signedOut,

  /// Réseau absent, site injoignable, réponse refusée. Rien d'autre à faire
  /// que de réessayer plus tard — la sortie reste sur le téléphone, elle ne
  /// se perd jamais.
  failed,
}

@immutable
class RideUploadResult {
  const RideUploadResult(this.status, {this.activityId, this.message});

  final RideUploadStatus status;

  /// L'identifiant de l'activité côté site, quand [status] vaut [RideUploadStatus.ok].
  final int? activityId;

  /// Un détail à montrer au cycliste sur un échec — jamais sur un succès, où
  /// il n'y a rien à ajouter à « envoyée ».
  final String? message;
}

/// Envoie une sortie enregistrée à `/api/imported_activities`, **par le pot de
/// cookies du WebView** — même principe que `RouteCatalogFetch` : l'appli ne
/// détient aucun jeton, la session est celle que Compte a laissée. Un client
/// HTTP natif devrait extraire ce cookie du pot d'Android pour le rejouer,
/// une API que `webview_flutter` n'expose pas.
///
/// Contrairement à `RouteCatalogFetch`, l'appel est une **écriture** : il faut
/// le jeton CSRF de la page, posé dans une balise `<meta>` par
/// `csrf_meta_tags` — un fichier statique comme `robots.txt` n'en a pas.
/// L'origine chargée est donc `/import/fit`, la page que le site réserve déjà
/// à l'atterrissage d'un `.fit` : si personne n'est connecté elle redirige
/// vers l'accueil, qui porte la même balise, donc dans tous les cas la page
/// chargée a un jeton à donner — c'est l'appel à l'API, avec
/// `Accept: application/json`, qui tranche ensuite « pas connecté » (401)
/// de « pas de réseau ».
class RideUploadFetch {
  const RideUploadFetch({
    this.baseUrl = sportsScopeBaseUrl,
    this.timeout = const Duration(seconds: 45),
  });

  final String baseUrl;

  /// Plus long qu'un `RouteCatalogFetch` : la charge utile porte toute la
  /// trace, pas une poignée d'itinéraires, et part sur la même connexion que
  /// celle du cycliste en train de rouler.
  final Duration timeout;

  static const _channel = 'SportsScopeUpload';
  static const _originPath = '/import/fit';

  Future<RideUploadResult> run(Map<String, dynamic> payload) async {
    final answer = Completer<RideUploadResult>();
    late final WebViewController controller;
    Timer? retries;
    var asked = false;

    void finish(RideUploadResult result) {
      if (answer.isCompleted) return;
      retries?.cancel();
      answer.complete(result);
    }

    void ask() {
      // Un seul envoi : redemander comme le fait `RouteCatalogFetch` (simple
      // lecture, rejouable sans effet de bord) dupliquerait ici la sortie côté
      // site à chaque tentative du minuteur de secours.
      if (asked) return;
      asked = true;
      controller.runJavaScript(_scriptFor(payload)).catchError((Object e) {
        debugPrint('[envoi sortie] script refusé : $e');
      });
    }

    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          _channel,
          onMessageReceived: (message) => finish(_decode(message.message)),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              debugPrint('[envoi sortie] origine chargée : $url');
              ask();
            },
            onWebResourceError: (error) {
              // Seule une erreur de cadre principal est fatale — voir
              // `RouteCatalogFetch` pour la même garde.
              if (error.isForMainFrame != true) {
                debugPrint('[envoi sortie] ressource ignorée : '
                    '${error.url} (${error.description})');
                return;
              }
              debugPrint('[envoi sortie] origine injoignable : '
                  '${error.description}');
              finish(const RideUploadResult(RideUploadStatus.failed));
            },
          ),
        );

      await controller.loadRequest(Uri.parse('$baseUrl$_originPath'));

      retries = Timer(const Duration(seconds: 4), ask);
    } catch (e) {
      debugPrint('[envoi sortie] impossible : $e');
      retries?.cancel();
      return const RideUploadResult(RideUploadStatus.failed);
    }

    final result = await answer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('[envoi sortie] pas de réponse en ${timeout.inSeconds} s');
        retries?.cancel();
        return const RideUploadResult(RideUploadStatus.failed);
      },
    );

    retries.cancel();
    debugPrint('[envoi sortie] ${result.status.name}');
    return result;
  }

  String _scriptFor(Map<String, dynamic> payload) => '''
    (function () {
      var payload = ${jsonEncode(payload)};
      var send = function (result) {
        try { $_channel.postMessage(JSON.stringify(result)); } catch (e) {}
      };
      try {
        var meta = document.querySelector('meta[name="csrf-token"]');
        var csrf = meta ? meta.getAttribute('content') : '';
        fetch('/api/imported_activities', {
          method: 'POST',
          credentials: 'same-origin',
          cache: 'no-store',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-CSRF-Token': csrf || ''
          },
          body: JSON.stringify(payload)
        }).then(function (response) {
          if (response.status === 401) return send({ status: 'signedOut' });
          if (response.ok) {
            return response.json().then(function (body) {
              send({ status: 'ok', body: body });
            });
          }
          return response.text().then(function (text) {
            send({ status: 'failed', code: response.status, body: text });
          });
        }).catch(function (e) {
          send({ status: 'failed', reason: String(e) });
        });
      } catch (e) {
        send({ status: 'failed', reason: String(e) });
      }
    })();
  ''';

  RideUploadResult _decode(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return const RideUploadResult(RideUploadStatus.failed);

      return switch (decoded['status']) {
        'ok' => RideUploadResult(
            RideUploadStatus.ok,
            activityId: _activityIdOf(decoded['body']),
          ),
        'signedOut' => const RideUploadResult(RideUploadStatus.signedOut),
        _ => RideUploadResult(
            RideUploadStatus.failed,
            message: decoded['reason']?.toString() ??
                (decoded['code'] != null ? 'HTTP ${decoded['code']}' : null),
          ),
      };
    } catch (e) {
      debugPrint('[envoi sortie] réponse illisible : $e');
      return const RideUploadResult(RideUploadStatus.failed);
    }
  }

  int? _activityIdOf(Object? body) {
    if (body is! Map) return null;
    final activity = body['activity'];
    if (activity is! Map) return null;
    final id = activity['id'];
    return id is num ? id.round() : null;
  }
}
