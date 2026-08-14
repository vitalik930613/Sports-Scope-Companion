import 'dart:async';

import 'package:flutter/material.dart';

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
  /// Niveau de zoom des tuiles (256 px). Choix visuel pour la v1 : à ajuster
  /// si la couverture affichée s'avère trop large ou trop étroite.
  static const _zoom = 8;

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
/// repère du cycliste, et — en option — l'heure de la frame affichée.
///
/// **Se dimensionne sur sa case, pas l'inverse.** Sans [size], elle mesure
/// l'espace que [LayoutBuilder] lui donne et choisit combien de tuiles il
/// faut pour le couvrir ([_coverage]) — c'est ce qui fait qu'une case posée
/// en 3×3 se retrouve couverte de tuiles plutôt que d'un unique carré minuscule
/// centré dedans. Avec [size] (la vue plein écran, dans un [InteractiveViewer]
/// qui a besoin d'un enfant de taille connue pour le transformer), la même
/// logique s'applique à cette taille fixe.
class RadarCanvas extends StatelessWidget {
  const RadarCanvas({
    super.key,
    required this.catalog,
    required this.frame,
    required this.fix,
    required this.zoom,
    this.size,
    this.showClock = false,
  });

  final RainviewerCatalog catalog;
  final RainviewerFrame frame;
  final GpsFix fix;
  final int zoom;

  /// `null` : remplit l'espace disponible ([LayoutBuilder]) — le cas de la
  /// case de grille. Fixe : la vue plein écran, dont l'[InteractiveViewer]
  /// a besoin d'un enfant borné à transformer.
  final Size? size;

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
    final fixedSize = size;
    if (fixedSize != null) {
      return _grid(fixedSize.width, fixedSize.height);
    }

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
          for (var dy = -halfY; dy <= halfY; dy++)
            for (var dx = -halfX; dx <= halfX; dx++)
              Positioned(
                left: (dx + halfX) * tileSizeW,
                top: (dy + halfY) * tileSizeH,
                width: tileSizeW,
                height: tileSizeH,
                child: Opacity(
                  opacity: 0.85,
                  child: Image.network(
                    catalog.tileUrl(frame, z: zoom, x: centerX + dx, y: centerY + dy),
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

/// La vue plein écran ouverte au tap sur la case : un canevas plus large, et
/// un vrai zoom/pan ([InteractiveViewer], natif Flutter — rien à ajouter au
/// projet) puisque rien ici ne dispute le geste à une navigation entre pages.
class _PrecipRadarDetailPage extends StatefulWidget {
  const _PrecipRadarDetailPage({required this.recorder, required this.client});

  final RideRecorder recorder;
  final RainviewerClient client;

  @override
  State<_PrecipRadarDetailPage> createState() => _PrecipRadarDetailPageState();
}

class _PrecipRadarDetailPageState extends State<_PrecipRadarDetailPage> {
  /// Un canevas plus large qu'en case de grille, à la même échelle de tuile
  /// (même [_zoom] que [_PrecipRadarBlockViewState]) : plus de contexte
  /// autour du cycliste, le zoom optique de [InteractiveViewer] fait le
  /// reste pour regarder de plus près.
  static const _canvasSize = 700.0;
  static const _zoom = 8;

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
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Précipitations'),
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
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: RadarCanvas(
                        catalog: catalog,
                        frame: frame,
                        fix: fix,
                        zoom: _zoom,
                        size: const Size(_canvasSize, _canvasSize),
                      ),
                    ),
                  ),
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
                      '© OpenStreetMap, © CARTO, © RainViewer',
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
