import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../navigation/navigation_target.dart';

/// Une frame du catalogue RainViewer : un horodatage Unix (secondes) et le
/// chemin à insérer dans le gabarit d'URL de tuile.
class RainviewerFrame {
  const RainviewerFrame({required this.time, required this.path});

  final int time;
  final String path;
}

/// Le catalogue de frames renvoyé par notre proxy (`/api/rainviewer`, voir
/// `RainviewerController` côté site) : l'hôte des tuiles, et les frames dans
/// l'ordre chronologique — passé récent puis prévision courte ("nowcast").
class RainviewerCatalog {
  const RainviewerCatalog({required this.host, required this.frames});

  final String host;
  final List<RainviewerFrame> frames;

  /// L'URL d'une tuile XYZ pour [frame] — couleur 2 ("universal blue"),
  /// lissage + affichage neige/pluie par défaut (`1_1`), même gabarit que la
  /// doc RainViewer (rainviewer.com/api.html).
  String tileUrl(RainviewerFrame frame, {required int z, required int x, required int y}) =>
      '$host${frame.path}/256/$z/$x/$y/2/1_1.png';
}

/// Récupère et garde en cache le catalogue de frames RainViewer, via notre
/// proxy Rails public (`/api/rainviewer`) — pas d'appel direct à RainViewer
/// depuis l'appli, même raison que [UpdateChecker] pour `companion_version`
/// (`update_checker.dart`) : endpoint public côté site, `dart:io` plutôt que
/// le bridge WebView qui n'a de sens que pour des données de compte.
///
/// **Une panne ne touche jamais le cache** : le radar de sortie n'a pas à
/// disparaître parce qu'un relevé a échoué, il continue d'afficher le dernier
/// catalogue connu jusqu'au prochain relevé réussi.
class RainviewerClient {
  RainviewerClient({
    this.baseUrl = sportsScopeBaseUrl,
    Future<String?> Function(Uri)? fetch,
  }) : _fetch = fetch ?? _fetchOverHttp;

  final String baseUrl;
  final Future<String?> Function(Uri) _fetch;

  /// RainViewer republie son catalogue toutes les ~10 minutes (déjà mis en
  /// cache une fois de plus côté site) — pas besoin de relever plus souvent.
  static const _freshness = Duration(minutes: 5);

  RainviewerCatalog? _cached;
  DateTime? _cachedAt;

  /// Le catalogue courant, relevé si le dernier date de plus de [_freshness].
  /// `null` seulement si aucun relevé n'a jamais réussi.
  Future<RainviewerCatalog?> catalog() async {
    final cachedAt = _cachedAt;
    if (cachedAt != null && DateTime.now().difference(cachedAt) < _freshness) {
      return _cached;
    }

    try {
      final body = await _fetch(Uri.parse('$baseUrl/api/rainviewer'));
      if (body == null) return _cached;

      final parsed = _parse(body);
      if (parsed == null) return _cached;

      _cached = parsed;
      _cachedAt = DateTime.now();
      return _cached;
    } catch (e) {
      return _cached;
    }
  }

  static RainviewerCatalog? _parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (e) {
      return null;
    }
    if (json is! Map) return null;

    final host = json['host'];
    final frames = json['frames'];
    if (host is! String || frames is! List) return null;

    final parsedFrames = <RainviewerFrame>[];
    for (final f in frames) {
      if (f is! Map) continue;
      final time = f['time'];
      final path = f['path'];
      if (time is int && path is String) {
        parsedFrames.add(RainviewerFrame(time: time, path: path));
      }
    }
    if (parsedFrames.isEmpty) return null;

    return RainviewerCatalog(host: host, frames: parsedFrames);
  }

  static Future<String?> _fetchOverHttp(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      return await response.transform(const Utf8Decoder()).join();
    } finally {
      client.close(force: true);
    }
  }
}

/// Le fond de carte sous les tuiles de précipitations — RainViewer ne fournit
/// que la précipitation, sur fond transparent : sans lui, les taches flottent
/// sans aucun repère (route, ville, relief) pour les situer. CartoDB Dark
/// Matter sans étiquettes : gratuit, sans clé, et déjà sombre comme le reste
/// du tableau de bord. Attribution requise : « © OpenStreetMap contributors,
/// © CARTO » (affichée dans la vue plein écran, voir `precip_radar_block.dart`
/// — pas dans la case de grille, trop petite pour la porter lisiblement).
///
/// Sous-domaines tournants (`a`–`d`), le gabarit officiellement documenté par
/// CartoDB — pas le domaine nu, dont le comportement s'est avéré moins fiable
/// en usage réel (tuile d'erreur reçue par endroits) alors que ce gabarit-ci
/// est celui que tous les clients de carte utilisent.
const _cartoSubdomains = ['a', 'b', 'c', 'd'];

String basemapTileUrl(int z, int x, int y) {
  final subdomain = _cartoSubdomains[(x + y).abs() % _cartoSubdomains.length];
  return 'https://$subdomain.basemaps.cartocdn.com/dark_nolabels/$z/$x/$y.png';
}

/// Calcul de tuile Web Mercator (slippy map), en coordonnées fractionnaires —
/// la partie entière donne la tuile, la partie décimale la position exacte du
/// point dans cette tuile. C'est cette précision qui permet de poser le repère
/// du cycliste à son vrai endroit plutôt qu'au centre de sa tuile.
double lonToTileX(double lon, int z) => (lon + 180) / 360 * (1 << z);

double latToTileY(double lat, int z) {
  final latRad = lat * math.pi / 180;
  return (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * (1 << z);
}
