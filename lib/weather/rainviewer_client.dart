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

  /// Le même gabarit, en template `{z}/{x}/{y}` littéral — ce qu'attend
  /// `TileLayer.urlTemplate` (`package:flutter_map`) dans la vue plein écran
  /// de `precip_radar_block.dart`, qui résout elle-même les coordonnées à
  /// chaque geste de zoom/pan plutôt que de recevoir des tuiles déjà
  /// résolues comme le fait la case de grille ([tileUrl]).
  String tileUrlTemplate(RainviewerFrame frame) => '$host${frame.path}/256/{z}/{x}/{y}/2/1_1.png';

  /// Le zoom XYZ maximal que sert vraiment RainViewer — **vérifié en
  /// regardant le contenu des tuiles**, pas seulement leur code HTTP : au-delà
  /// de 7, le serveur répond 200 avec un PNG parfaitement valide qui affiche
  /// littéralement « Zoom Level Not Supported » en pixels plutôt que de
  /// refuser la requête. Une case de grille qui veut un fond de carte plus
  /// serré (voir `precip_radar_block.dart`) doit donc composer sa surcouche
  /// de précipitations à ce zoom-ci, mise à l'échelle et alignée sur le repère
  /// écran du fond de carte — jamais lui demander directement le zoom du fond.
  static const maxZoom = 7;
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
/// sans aucun repère (route, ville, relief) pour les situer.
///
/// swisstopo (`wmts.geo.admin.ch`) plutôt qu'un fournisseur tiers gratuit
/// générique : gratuit, sans clé, et surtout un vrai service public pensé
/// pour être intégré — un premier essai avec les tuiles CartoDB anonymes a
/// servi une tuile d'erreur (« Zoom Level Not Supported ») en usage réel
/// alors qu'un appel isolé passait, signe d'un plan gratuit qui tolère la
/// consultation occasionnelle mais pas l'intégration dans une appli. Même
/// gabarit WMTS que `app/javascript/mapStyles.ts` côté site
/// (`ch.swisstopo.pixelkarte-grau`) : gris plutôt que couleur, pour ne pas
/// concurrencer les teintes des précipitations par-dessus.
///
/// Couverture Suisse + abords seulement — même périmètre que les autres
/// données auto-hébergées du projet (BRouter, POI). Hors de cette zone, le
/// service renvoie une vraie erreur HTTP (pas une image trompeuse comme
/// CartoDB), et `errorBuilder` (`precip_radar_block.dart`) retombe sur un
/// fond uni. Attribution requise : « © swisstopo » (affichée dans la vue
/// plein écran — pas dans la case de grille, trop petite pour la porter
/// lisiblement).
String basemapTileUrl(int z, int x, int y) =>
    'https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-grau/default/current/3857/$z/$x/$y.jpeg';

/// Le même gabarit, en template `{z}/{x}/{y}` littéral pour `TileLayer` —
/// voir [RainviewerCatalog.tileUrlTemplate], même raison.
const basemapTileUrlTemplate =
    'https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-grau/default/current/3857/{z}/{x}/{y}.jpeg';

/// Calcul de tuile Web Mercator (slippy map), en coordonnées fractionnaires —
/// la partie entière donne la tuile, la partie décimale la position exacte du
/// point dans cette tuile. C'est cette précision qui permet de poser le repère
/// du cycliste à son vrai endroit plutôt qu'au centre de sa tuile.
double lonToTileX(double lon, int z) => (lon + 180) / 360 * (1 << z);

double latToTileY(double lat, int z) {
  final latRad = lat * math.pi / 180;
  return (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * (1 << z);
}
