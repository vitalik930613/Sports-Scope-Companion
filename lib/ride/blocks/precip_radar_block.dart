import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../recording/gps_fix.dart';
import '../../recording/ride_recorder.dart';
import '../../weather/rainviewer_client.dart';
import 'block_card.dart';

/// Récupère le catalogue et anime la frame courante, pour le compte d'une
/// vue — factorisé parce que la case de grille ([PrecipRadarBlockView]) et la
/// vue plein écran ([_PrecipRadarDetailPage]) en ont chacune besoin, avec le
/// même cycle de vie (un relevé, puis une boucle jusqu'à la fin de la vue).
class _FrameAnimator {
  _FrameAnimator({required this.client, required this.onChanged});

  final RainviewerClient client;
  final VoidCallback onChanged;

  static const _frameInterval = Duration(milliseconds: 700);

  RainviewerCatalog? catalog;
  Timer? _timer;
  int frameIndex = 0;

  Future<void> start() async {
    catalog = await client.catalog();
    onChanged();
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    final count = catalog?.frames.length ?? 0;
    if (count < 2) return;

    _timer = Timer.periodic(_frameInterval, (_) {
      frameIndex = (frameIndex + 1) % count;
      onChanged();
    });
  }

  void dispose() => _timer?.cancel();
}

/// L'heure de [frame], dans le fuseau du téléphone — c'est la question posée
/// par « c'est quand, cette image ? », pas un délai relatif qu'il faudrait
/// recalculer de tête.
String _frameClock(RainviewerFrame frame) {
  final dt = DateTime.fromMillisecondsSinceEpoch(frame.time * 1000).toLocal();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// « Maintenant », ou son décalage — le complément de [_frameClock] : l'heure
/// dit *quand*, ceci dit *à quelle distance de maintenant*, ce qui répond
/// directement à « c'est déjà passé ou c'est une prévision ? ».
String _frameCaption(RainviewerFrame frame) {
  final dt = DateTime.fromMillisecondsSinceEpoch(frame.time * 1000);
  final deltaMin = dt.difference(DateTime.now()).inMinutes;
  if (deltaMin.abs() <= 2) return 'Maintenant';
  return deltaMin > 0 ? 'Prévision +$deltaMin min' : 'Il y a ${-deltaMin} min';
}

/// L'animation radar des précipitations (RainViewer), centrée sur la position
/// GPS courante — voir `PrecipRadarBlock` (`dashboard_block.dart`).
///
/// **Remplit toute la case, à n'importe quelle taille** — contrairement à la
/// plupart des blocs, qui composent à une taille naturelle fixe que
/// [ScaleToFit] réduit ou centre ensuite ([BlockCard]/[BlockSurface]). Cette
/// convention centre un contenu de taille fixe dans la case plutôt que de le
/// faire grandir jusqu'aux bords, ce qui convient à un chiffre ou une jauge
/// mais laisserait une carte flotter, minuscule, au milieu d'une grande case.
/// Ici c'est l'inverse : [RadarCanvas] mesure sa case via `LayoutBuilder` et
/// choisit combien de tuiles il faut pour la couvrir.
///
/// Boucle sur les frames du catalogue — passé récent puis prévision courte
/// ("nowcast") — dans l'ordre où [RainviewerClient] les renvoie.
///
/// **`absent` n'est pas `vide`**, même règle que [RadarBlockView] pour le
/// radar arrière : pas de GPS et pas de catalogue sont deux états distincts,
/// écrits en toutes lettres plutôt que de laisser deviner un radar figé. Ces
/// deux états-là restent des [BlockCard] à taille naturelle : ce sont des
/// phrases, pas une carte à faire grandir.
///
/// **Pas de zoom ni de glissé dans la case.** Une case de grille peut vivre
/// dans une page qui défile au geste : y répondre au pincement ou au glissé
/// volerait ce geste à la navigation entre pages, exactement ce que
/// `map_swipe_zone.dart` existe pour éviter sur la carte plein écran. La case
/// se tape pour ouvrir une vue dédiée, où le zoom ne dispute le geste à rien.
class PrecipRadarBlockView extends StatefulWidget {
  PrecipRadarBlockView({
    super.key,
    required this.recorder,
    this.color,
    this.textColor,
    RainviewerClient? client,
  }) : client = client ?? RainviewerClient();

  final RideRecorder recorder;

  /// Fond de la carte, réglé dans l'éditeur — voir `DashboardBlock.color`.
  final Color? color;
  final Color? textColor;

  /// Injectable pour les tests ; par défaut un client qui parle au vrai proxy
  /// du site.
  final RainviewerClient client;

  @override
  State<PrecipRadarBlockView> createState() => _PrecipRadarBlockViewState();
}

class _PrecipRadarBlockViewState extends State<PrecipRadarBlockView> {
  /// Niveau de zoom des tuiles (256 px). 8 montrait presque toute la Suisse
  /// dans la case — chaque tuile y fait ~107 km de large à cette latitude ;
  /// 11 en fait ~13 km, une échelle cohérente avec l'horizon de la prévision
  /// RainViewer (nowcast : ~30-60 min, donc un système qui approche vient de
  /// quelques dizaines de km, pas de tout le pays).
  static const _zoom = 11;

  late final _FrameAnimator _animator;

  @override
  void initState() {
    super.initState();
    _animator = _FrameAnimator(client: widget.client, onChanged: _onChanged)..start();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _animator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.recorder,
      builder: (context, _) {
        final fix = widget.recorder.lastFix;
        if (fix == null) {
          return BlockCard(
            title: 'Précipitations',
            lines: const ['Pas de GPS.'],
            color: widget.color,
            textColor: widget.textColor,
          );
        }

        final catalog = _animator.catalog;
        if (catalog == null || catalog.frames.isEmpty) {
          return BlockCard(
            title: 'Précipitations',
            lines: const ['Radar indisponible.'],
            color: widget.color,
            textColor: widget.textColor,
          );
        }

        final frame = catalog.frames[_animator.frameIndex % catalog.frames.length];
        return GestureDetector(
          onTap: () => _openDetail(context),
          child: _FillCard(
            background: widget.color,
            child: RadarCanvas(
              catalog: catalog,
              frame: frame,
              fix: fix,
              zoom: _zoom,
              showClock: true,
            ),
          ),
        );
      },
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PrecipRadarDetailPage(recorder: widget.recorder, client: widget.client),
        fullscreenDialog: true,
      ),
    );
  }
}

/// Le cadre d'une carte qui doit remplir sa case plutôt que d'y centrer un
/// contenu à taille naturelle — même fond et mêmes coins que [BlockSurface],
/// sans son [ScaleToFit] : c'est [RadarCanvas] qui décide de sa propre
/// composition une fois la taille réelle connue, pas une mise à l'échelle
/// après coup d'un contenu déjà figé.
class _FillCard extends StatelessWidget {
  const _FillCard({required this.child, this.background});

  final Widget child;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: background ?? BlockCard.background,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.hardEdge,
        child: child,
      );
}

/// La grille de tuiles composée : fond de carte, précipitations par-dessus,
/// repère du cycliste, et — en option — l'heure de la frame affichée. Sert
/// uniquement la case de grille ([PrecipRadarBlockView]) — la vue plein
/// écran ([_PrecipRadarDetailPage]) affiche une vraie carte interactive
/// (`package:flutter_map`) plutôt que ce composite figé.
///
/// **Se dimensionne sur sa case, pas l'inverse.** Elle mesure l'espace que
/// [LayoutBuilder] lui donne et choisit combien de tuiles il faut pour le
/// couvrir ([_coverage]) — c'est ce qui fait qu'une case posée en 3×3 se
/// retrouve couverte de tuiles plutôt que d'un unique carré minuscule centré
/// dedans.
class RadarCanvas extends StatelessWidget {
  const RadarCanvas({
    super.key,
    required this.catalog,
    required this.frame,
    required this.fix,
    required this.zoom,
    this.showClock = false,
  });

  final RainviewerCatalog catalog;
  final RainviewerFrame frame;
  final GpsFix fix;
  final int zoom;

  final bool showClock;

  /// Taille visée d'une tuile à l'écran, en px logiques — densité de la
  /// grille dynamique : assez petit pour ne pas sur-couvrir une grande case
  /// de trop peu de tuiles (perte de détail géographique), assez grand pour
  /// ne pas multiplier les requêtes réseau sur une case minuscule.
  static const _targetTilePx = 100.0;

  /// Repli quand la case ne borne pas sa taille (par ex. dans une colonne non
  /// contrainte) — un carré raisonnable plutôt qu'une exception.
  static const _fallbackPx = 200.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : _fallbackPx;
        final height = constraints.hasBoundedHeight ? constraints.maxHeight : _fallbackPx;
        return _grid(width, height);
      },
    );
  }

  Widget _grid(double width, double height) {
    final tilesX = _coverage(width);
    final tilesY = _coverage(height);
    final halfX = tilesX ~/ 2;
    final halfY = tilesY ~/ 2;
    final tileSizeW = width / tilesX;
    final tileSizeH = height / tilesY;

    final xFrac = lonToTileX(fix.lng, zoom);
    final yFrac = latToTileY(fix.lat, zoom);
    final centerX = xFrac.floor();
    final centerY = yFrac.floor();
    // Décalage du cycliste dans sa tuile, en fraction de tuile (0..1) —
    // reporté en pixels sur la grille composée, pour un repère à sa position
    // exacte plutôt qu'au centre géométrique de la grille.
    final offsetXFrac = xFrac - centerX;
    final offsetYFrac = yFrac - centerY;

    // La surcouche de précipitations, à son propre zoom plafonné — voir
    // `RainviewerCatalog.maxZoom`. `precipScale` dit combien de tuiles du
    // fond de carte fait une seule tuile précip (toujours un entier, `zoom`
    // valant au moins `maxZoom` en pratique) ; `baseLeftTile`/`baseTopTile`
    // sont l'origine du fond de carte affiché, dans le même repère « tuile
    // du fond » que sert à positionner ses propres tuiles juste au-dessus.
    final precipZoom = math.min(zoom, RainviewerCatalog.maxZoom);
    final zoomDiff = zoom - precipZoom;
    final precipScale = 1 << zoomDiff;
    final xFracP = lonToTileX(fix.lng, precipZoom);
    final yFracP = latToTileY(fix.lat, precipZoom);
    final centerXP = xFracP.floor();
    final centerYP = yFracP.floor();
    final baseLeftTile = centerX - halfX;
    final baseTopTile = centerY - halfY;
    final precipTileW = tileSizeW * precipScale;
    final precipTileH = tileSizeH * precipScale;
    // Une seule tuile précip couvrant déjà `precipScale` tuiles du fond de
    // carte (16 à zoom 11), une marge fixe de ±1 suffit toujours à couvrir
    // toute la case, quelle que soit sa taille — pas besoin de la faire
    // dépendre de [tilesX]/[tilesY].
    const precipHalf = 1;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // Fond de carte : sans lui les tuiles de précipitations (fond
          // transparent) flottent sans aucun repère géographique.
          for (var dy = -halfY; dy <= halfY; dy++)
            for (var dx = -halfX; dx <= halfX; dx++)
              Positioned(
                left: (dx + halfX) * tileSizeW,
                top: (dy + halfY) * tileSizeH,
                width: tileSizeW,
                height: tileSizeH,
                child: Image.network(
                  basemapTileUrl(zoom, centerX + dx, centerY + dy),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(color: Color(0xFF10151C)),
                ),
              ),
          for (var dy = -precipHalf; dy <= precipHalf; dy++)
            for (var dx = -precipHalf; dx <= precipHalf; dx++)
              Positioned(
                // RainViewer ne sert ses tuiles qu'à `RainviewerCatalog.maxZoom`
                // (vérifié en pixels, pas juste au code HTTP — au-delà, un PNG
                // 200 qui affiche « Zoom Level Not Supported »). Bien plus
                // grossier qu'un fond de carte serré : chaque tuile précip
                // couvre alors plusieurs tuiles du fond, et on la met à
                // l'échelle et on la positionne dans le même repère écran que
                // lui plutôt que dans sa propre grille indépendante.
                left: ((centerXP + dx) * precipScale - baseLeftTile) * tileSizeW,
                top: ((centerYP + dy) * precipScale - baseTopTile) * tileSizeH,
                width: precipTileW,
                height: precipTileH,
                child: Opacity(
                  opacity: 0.85,
                  child: Image.network(
                    catalog.tileUrl(frame, z: precipZoom, x: centerXP + dx, y: centerYP + dy),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => const SizedBox(),
                  ),
                ),
              ),
          Positioned(
            left: halfX * tileSizeW + offsetXFrac * tileSizeW - 5,
            top: halfY * tileSizeH + offsetYFrac * tileSizeH - 5,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 2),
              ),
            ),
          ),
          if (showClock)
            Positioned(
              left: 6,
              bottom: 6,
              child: _ClockChip(frame: frame),
            ),
        ],
      ),
    );
  }

  /// Combien de tuiles il faut pour couvrir [px] px à [_targetTilePx] chacune
  /// — au moins une, toujours impair (une tuile centrale exacte plutôt qu'une
  /// frontière entre deux), plafonné à 7 pour ne pas multiplier les requêtes
  /// réseau si jamais une case se retrouvait sans borne réaliste.
  static int _coverage(double px) {
    final raw = (px / _targetTilePx).ceil().clamp(1, 7);
    return raw | 1;
  }
}

class _ClockChip extends StatelessWidget {
  const _ClockChip({required this.frame});

  final RainviewerFrame frame;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _frameClock(frame),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );
}

/// La vue plein écran ouverte au tap sur la case : une vraie carte
/// interactive ([FlutterMap], `package:flutter_map` — pur Dart, aucun code
/// natif à configurer) plutôt que le composite figé de [RadarCanvas]. Rien
/// ici ne dispute le geste de pincement/glissé à une navigation entre pages
/// (contrairement à la case, voir la note de classe de [PrecipRadarBlockView]),
/// donc rien n'empêche un vrai zoom qui recharge des tuiles plus détaillées.
///
/// Le fond de carte suit le zoom librement ; la surcouche de précipitations
/// est plafonnée à [RainviewerCatalog.maxZoom] via `maxNativeZoom` — au-delà,
/// `TileLayer` réutilise et agrandit les tuiles de ce zoom plutôt que d'en
/// redemander à un service qui ne les sert pas (voir la note sur
/// [RainviewerCatalog.maxZoom] : servies quand même, elles affichent
/// littéralement « Zoom Level Not Supported » en pixels).
class _PrecipRadarDetailPage extends StatefulWidget {
  const _PrecipRadarDetailPage({required this.recorder, required this.client});

  final RideRecorder recorder;
  final RainviewerClient client;

  @override
  State<_PrecipRadarDetailPage> createState() => _PrecipRadarDetailPageState();
}

class _PrecipRadarDetailPageState extends State<_PrecipRadarDetailPage> {
  static const _initialZoom = 11.0;
  static const _minZoom = 5.0;
  static const _maxZoom = 16.0;

  late final _FrameAnimator _animator;

  @override
  void initState() {
    super.initState();
    _animator = _FrameAnimator(client: widget.client, onChanged: _onChanged)..start();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _animator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // `foregroundColor` explicite : sans lui le titre et la flèche retour
      // héritent d'un contraste indéterminé sur fond noir, au lieu du blanc
      // du reste de cette page. Tout l'en-tête ferme la vue au tap — pas
      // seulement la flèche retour, minuscule et donc facile à manquer sur
      // un fond aussi peu contrasté.
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: const SizedBox(
            height: kToolbarHeight,
            width: double.infinity,
            child: Center(
              child: Text('Précipitations'),
            ),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.recorder,
        builder: (context, _) {
          final fix = widget.recorder.lastFix;
          final catalog = _animator.catalog;

          if (fix == null || catalog == null || catalog.frames.isEmpty) {
            return Center(
              child: Text(
                fix == null ? 'Pas de GPS.' : 'Radar indisponible.',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            );
          }

          final frame = catalog.frames[_animator.frameIndex % catalog.frames.length];
          final center = ll.LatLng(fix.lat, fix.lng);

          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: _initialZoom,
                    minZoom: _minZoom,
                    maxZoom: _maxZoom,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: basemapTileUrlTemplate,
                      userAgentPackageName: 'ch.logicraft.sports.companion',
                    ),
                    Opacity(
                      opacity: 0.85,
                      child: TileLayer(
                        urlTemplate: catalog.tileUrlTemplate(frame),
                        maxNativeZoom: RainviewerCatalog.maxZoom,
                        userAgentPackageName: 'ch.logicraft.sports.companion',
                      ),
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: center,
                          width: 16,
                          height: 16,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_frameClock(frame)} · ${_frameCaption(frame)}',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const Text(
                      '© swisstopo, © RainViewer',
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
