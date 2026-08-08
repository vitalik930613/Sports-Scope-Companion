import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import '../navigation/navigation_target.dart' show sportsScopeBaseUrl;
import '../recording/gps_fix.dart';

/// Filet natif pour les alertes de virage — le complément de [TurnProximity].
///
/// La navigation « normale » (bandeau, son, vibration) tourne entièrement dans
/// le JavaScript du WebView (voir `navigation_web_view.dart`), y compris sa
/// propre position GPS. Un écran réellement verrouillé fige ce WebView, et avec
/// lui toute alerte — alors que l'enregistrement continue sans broncher, protégé
/// par le service de premier plan de [RideRecorder]. [TurnProximity] comble déjà
/// ce trou pour *le retour automatique à la carte*, mais seulement pour le
/// virage que la page a eu le temps d'annoncer avant de se taire.
///
/// Ceci va plus loin : la liste **complète** des virages du tracé, récupérée une
/// fois par l'API publique du site (pas besoin de session — c'est le même jeton
/// que [NavigationTarget] porte déjà), pour continuer à vibrer à chaque virage
/// même si le WebView reste figé sur toute la sortie, pas seulement jusqu'au
/// prochain.
///
/// Explicitement un premier jet : une seule alerte générique par virage (pas
/// de distinction gauche/droite/rond-point), pas de rattrapage après un
/// reroutage en pleine veille, et rien tant que [NavigationTarget.shareToken]
/// est absent (reprise, navigation libre) — la page seule connaît alors le
/// tracé.
///
/// L'alerte est double, vibration **et** son ([NativeTurnAlertSound]) : les
/// trois `HapticFeedback.heavyImpact()` du premier jet passaient par le retour
/// haptique de la vue (`View.performHapticFeedback`), pensé pour confirmer un
/// tap d'interface — mesuré trop faible au poignet en plein vent. Le paquet
/// `vibration` parle directement au `Vibrator` Android, à l'amplitude
/// maximale quand l'appareil le permet.
class NativeVoiceHint {
  const NativeVoiceHint({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

/// Va chercher les virages d'un itinéraire par son jeton de partage, en HTTP
/// direct — `/api/routes/shared/:token` ne demande aucune session (voir
/// `RoutesController#shared`), donc rien du détour par un WebView invisible que
/// fait `RouteCatalogFetch` pour parler au compte. `dart:io` évite d'ajouter une
/// dépendance pour un unique GET.
Future<List<NativeVoiceHint>?> fetchRouteVoiceHints(
  String shareToken, {
  String baseUrl = sportsScopeBaseUrl,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$baseUrl/api/routes/shared/$shareToken');
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      debugPrint('[virages] ${response.statusCode} sur $uri');
      return null;
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final route = decoded['route'];
    final hints = route is Map ? route['voice_hints'] : null;
    if (hints is! List) return null;

    return [
      for (final raw in hints)
        if (raw is Map &&
            raw['lat'] is num &&
            raw['lng'] is num)
          NativeVoiceHint(
            lat: (raw['lat'] as num).toDouble(),
            lng: (raw['lng'] as num).toDouble(),
          ),
    ];
  } catch (e) {
    debugPrint('[virages] récupération impossible : $e');
    return null;
  } finally {
    client.close();
  }
}

/// Suit la progression le long des virages et dit quand vibrer.
///
/// Un curseur, pas une recherche du virage le plus proche à chaque tic : sur un
/// tracé qui repasse près de lui-même (aller-retour, boucle), le plus proche
/// n'est pas forcément le prochain. Le rattrapage ([_lookahead]) ne sert que le
/// cas où l'écran est resté verrouillé au travers de plusieurs virages : on
/// avance alors jusqu'au premier qui redevient plausible, sans revenir en
/// arrière.
class NativeTurnAlerts {
  NativeTurnAlerts(this._hints);

  final List<NativeVoiceHint> _hints;
  int _cursor = 0;

  /// Distance de déclenchement. Plus courte que celle du chien de garde
  /// ([TurnProximity], 110 m, qui ne fait que ramener l'écran à la carte) :
  /// ici la vibration *est* l'alerte, mieux vaut la vouloir franche que
  /// précoce.
  static const alertM = 60.0;

  /// Nombre de virages regardés en avance pour rattraper un signal perdu
  /// pendant plusieurs virages d'affilée.
  static const _lookahead = 4;

  bool get isDone => _cursor >= _hints.length;

  /// `true` exactement une fois par virage franchi — à l'appelant de vibrer.
  bool update(GpsFix? fix) {
    if (fix == null || isDone) return false;

    // Rattrapage : si un virage plus loin dans la liste est déjà plus proche
    // que le courant, la position a avancé pendant qu'on ne regardait pas.
    var bestIndex = _cursor;
    var bestDist = GpsFix.haversineM(
      fix.lat,
      fix.lng,
      _hints[_cursor].lat,
      _hints[_cursor].lng,
    );
    for (var i = _cursor + 1;
        i < _hints.length && i < _cursor + _lookahead;
        i++) {
      final d = GpsFix.haversineM(fix.lat, fix.lng, _hints[i].lat, _hints[i].lng);
      if (d < bestDist) {
        bestIndex = i;
        bestDist = d;
      }
    }
    _cursor = bestIndex;

    if (bestDist > alertM) return false;

    // Déclenché : le prochain virage devient celui d'après, qu'on l'ait
    // atteint pile ou pas — rester dessus ferait vibrer à chaque tic tant
    // qu'on ne s'en éloigne pas.
    _cursor++;
    return true;
  }
}

/// Vibre fort, quatre fois — même compte que le bip ([NativeTurnAlertSound]).
///
/// Passe par le `Vibrator` Android (paquet `vibration`) plutôt que par
/// `HapticFeedback` : seule cette voie donne accès à l'amplitude. Sur un
/// appareil qui ne la supporte pas, le paquet retombe sur la durée seule —
/// toujours plus franc que le retour haptique par défaut, pensé pour
/// confirmer un tap d'interface et non pour alerter au poignet en plein vent.
/// N'échoue jamais : un appareil sans vibreur ne doit pas faire tomber le bip
/// avec lui.
Future<void> nativeTurnAlertBuzz() async {
  try {
    await Vibration.vibrate(
      pattern: const [0, 300, 130, 300, 130, 300, 130, 300],
      intensities: const [0, 255, 0, 255, 0, 255, 0, 255],
    );
  } catch (e) {
    debugPrint('[virages] vibration impossible : $e');
  }
}

/// Joue le bip du filet natif de virages — même patron que `RadarAlertPlayer`
/// (`radar_alert_sound.dart`), réduit à un seul son chargé d'avance : au
/// moment où un virage arrive, il n'est plus temps d'ouvrir un fichier.
///
/// Son propre contexte audio (guidage de navigation, plutôt que de compter
/// sur celui posé par le radar) : le filet natif n'est pas gouverné par le
/// réglage radar du profil de sortie, il doit sonner même sur un profil qui
/// coupe les sons radar ou n'a pas de radar du tout.
class NativeTurnAlertSound {
  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceNavigationGuidance,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  AudioPlayer? _player;

  Future<void> warmUp() async {
    try {
      await AudioPlayer.global.setAudioContext(_context);
      final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource('sounds/turn_alert.wav'));
      _player = player;
    } catch (e) {
      debugPrint('[virages] son indisponible : $e');
    }
  }

  void play() {
    final player = _player;
    if (player == null) return;
    // Depuis le début, sans attendre : un bip déjà en cours est un bip qui
    // date d'avant, et c'est celui de maintenant qui compte.
    player.seek(Duration.zero).then((_) => player.resume()).catchError((
      Object e,
    ) {
      debugPrint('[virages] bip perdu : $e');
    });
  }

  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
  }
}
