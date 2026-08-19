import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../recording/gps_fix.dart';
import '../../recording/ride_recorder.dart';
import '../../weather/rainviewer_client.dart';
import 'block_card.dart';

/// Le repère du cycliste — même flèche que la carte de navigation
/// (`RouteNavigation.vue`, `updateLocationMarker` : chemin SVG
/// `M12 2 L20 21 L12 16 L4 21 Z` dans un viewBox 24×24, bleu Google Maps
/// `#4285F4`, liseré blanc) recopiée à la main en `CustomPainter` — pas de
/// rendu partagé possible entre la carte web (MapLibre GL JS) et ce widget
/// natif. Pointe vers le cap du cycliste ([headingDeg]) quand le GPS en
/// fournit un ; sans cap (à l'arrêt), pointe vers le haut plutôt que de
/// deviner — la carte de navigation, elle, a la boussole du téléphone en
/// repli, que ce petit composant n'a pas de raison de répliquer.
class _RiderArrow extends StatelessWidget {
  const _RiderArrow({this.headingDeg, this.size = 22});

  final double? headingDeg;
  final double size;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: (headingDeg ?? 0) * math.pi / 180,
        child: CustomPaint(
          size: Size(size, size),
          painter: _RiderArrowPainter(),
        ),
      );
}

class _RiderArrowPainter extends CustomPainter {
  static const _fill = Color(0xFF4285F4);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final path = Path()
      ..moveTo(12 * scale, 2 * scale)
      ..lineTo(20 * scale, 21 * scale)
      ..lineTo(12 * scale, 16 * scale)
      ..lineTo(4 * scale, 21 * scale)
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.4), 2, false);
    canvas.drawPath(path, Paint()..color = _fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * scale
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RiderArrowPainter oldDelegate) => false;
}

/// Récupère le catalogue et anime la frame courante, pour le compte d'une
/// vue — factorisé parce que la case de grille ([PrecipRadarBlockView]) et la
/// vue plein écran ([_PrecipRadarDetailPage]) en ont chacune besoin, avec le
/// même cycle de vie (un relevé, puis une boucle jusqu'à la fin de la vue).
///
/// Scrutable : [seekTo] fige l'animation sur une image précise — un tap ou
/// un glissé sur [_FrameTimeline] plutôt qu'un geste qui se perdrait à la
/// frame suivante de la boucle. [resume] reprend la lecture là où
/// l'animation en était avant l'arrêt sur image.
class _FrameAnimator {
  _FrameAnimator({required this.client, required this.onChanged});

  final RainviewerClient client;
  final VoidCallback onChanged;

  static const _frameInterval = Duration(milliseconds: 700);

  RainviewerCatalog? catalog;
  Timer? _timer;
  int frameIndex = 0;

  bool get isPaused => _paused;
  bool _paused = false;

  Future<void> start() async {
    catalog = await client.catalog();
    onChanged();
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (_paused) return;
    final count = catalog?.frames.length ?? 0;
    if (count < 2) return;

    _timer = Timer.periodic(_frameInterval, (_) {
      frameIndex = (frameIndex + 1) % count;
      onChanged();
    });
  }

  /// Fige l'animation sur [index] — jusqu'au prochain [seekTo] ou [resume].
  void seekTo(int index) {
    final count = catalog?.frames.length ?? 0;
    if (count == 0) return;

    _paused = true;
    _timer?.cancel();
    frameIndex = index.clamp(0, count - 1);
    onChanged();
  }

  /// Reprend la boucle après un [seekTo].
  void resume() {
    if (!_paused) return;
    _paused = false;
    _restart();
    onChanged();
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
              paused: _animator.isPaused,
              onScrub: _animator.seekTo,
              onResume: _animator.resume,
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
        // Jamais `height: double.infinity` — voir la note dans
        // `elevation_profile_surface.dart` : posée sur une page qui défile,
        // cette case reçoit une hauteur non bornée, et forcer
        // `double.infinity` dessus produit une contrainte tendue à l'infini,
        // invalide. [RadarCanvas], plus bas, sait déjà se dimensionner sur
        // une hauteur non bornée (`hasBoundedHeight`, `_fallbackPx`).
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
    this.paused = false,
    this.onScrub,
    this.onResume,
  });

  final RainviewerCatalog catalog;
  final RainviewerFrame frame;
  final GpsFix fix;
  final int zoom;

  final bool showClock;

  /// L'animation est-elle figée sur une image scrutée — voir [_FrameAnimator.isPaused].
  /// Sans effet tant que [showClock] est faux : pas de frise, rien à colorer.
  final bool paused;

  /// L'index de la frame la plus proche du point touché/glissé sur la
  /// frise — voir `_FrameAnimator.seekTo`. Ignoré tant que [showClock] est
  /// faux, comme [paused].
  final ValueChanged<int>? onScrub;

  /// Reprend la boucle après un arrêt sur image — voir `_FrameAnimator.resume`.
  /// N'apparaît (petite icône ▶) que si [paused] est vrai : reprendre n'a de
  /// sens que là, pas pendant que ça défile déjà.
  final VoidCallback? onResume;

  /// Taille visée d'une tuile à l'écran, en px logiques — densité de la
  /// grille dynamique. Proche de la taille native de la tuile (256 px) :
  /// plus loin de 256, plus une grande case a besoin de tuiles pour être
  /// couverte (187 à 100 px sur une case de 995×1568 — bien trop de
  /// requêtes réseau pour un simple bloc météo), sans gagner de netteté
  /// puisque la tuile ne peut de toute façon pas afficher plus de détail
  /// que sa résolution native.
  static const _targetTilePx = 200.0;

  /// Repli quand la case ne borne pas sa taille (par ex. dans une colonne non
  /// contrainte) — un carré raisonnable plutôt qu'une exception.
  static const _fallbackPx = 200.0;

  /// Taille de la flèche du cycliste — plus petite que les 34 px de la
  /// carte de navigation (`RouteNavigation.vue`) : cette case est souvent
  /// bien plus petite que l'écran plein d'une navigation.
  static const _riderSize = 20.0;

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
    // Des tuiles **carrées**, jamais étirées à la taille de la case : une
    // tuile source est 256×256, et `BoxFit.cover` dans une case non carrée
    // recadrerait chaque tuile différemment de sa voisine selon l'axe le
    // plus serré — les routes ne se raccorderaient plus d'une tuile à
    // l'autre (vérifié : les tuiles de swisstopo s'alignent parfaitement
    // entre elles quand on les recadre soi-même à la même échelle sur les
    // deux axes). La grille peut donc déborder légèrement la case ; le
    // `Stack` la coupe au bord comme toute case trop généreuse.
    const tileSize = _targetTilePx;

    final xFrac = lonToTileX(fix.lng, zoom);
    final yFrac = latToTileY(fix.lat, zoom);
    final centerX = xFrac.floor();
    final centerY = yFrac.floor();

    final centerPxX = width / 2;
    final centerPxY = height / 2;

    // La position **exacte** de l'utilisateur (xFrac/yFrac, pas seulement sa
    // tuile) tombe pile au centre de la case — pas la tuile qui la contient,
    // qui peut être décalée jusqu'à une demi-tuile selon l'endroit où le
    // cycliste se trouve dedans. Sans cette distinction, l'ancienne version
    // centrait la *tuile* et laissait le repère du cycliste dériver de la
    // case au fil de la position réelle, tantôt à gauche, tantôt à droite.
    double screenLeft(int worldTileX, double px) => centerPxX + (worldTileX - xFrac) * px;
    double screenTop(int worldTileY, double px) => centerPxY + (worldTileY - yFrac) * px;

    // La surcouche de précipitations, à son propre zoom plafonné — voir
    // `RainviewerCatalog.maxZoom`. `precipScale` dit combien de tuiles du
    // fond de carte fait une seule tuile précip (toujours un entier, `zoom`
    // valant au moins `maxZoom` en pratique).
    final precipZoom = math.min(zoom, RainviewerCatalog.maxZoom);
    final zoomDiff = zoom - precipZoom;
    final precipScale = 1 << zoomDiff;
    final xFracP = lonToTileX(fix.lng, precipZoom);
    final yFracP = latToTileY(fix.lat, precipZoom);
    final centerXP = xFracP.floor();
    final centerYP = yFracP.floor();
    final precipTileSize = tileSize * precipScale;
    double screenLeftP(int worldTileX) => centerPxX + (worldTileX - xFracP) * precipTileSize;
    double screenTopP(int worldTileY) => centerPxY + (worldTileY - yFracP) * precipTileSize;
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
                left: screenLeft(centerX + dx, tileSize),
                top: screenTop(centerY + dy, tileSize),
                width: tileSize,
                height: tileSize,
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
                left: screenLeftP(centerXP + dx),
                top: screenTopP(centerYP + dy),
                width: precipTileSize,
                height: precipTileSize,
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
            // Toujours pile au centre de la case, par construction — voir
            // `screenLeft`/`screenTop` plus haut.
            left: centerPxX - _riderSize / 2,
            top: centerPxY - _riderSize / 2,
            child: _RiderArrow(headingDeg: fix.headingDeg, size: _riderSize),
          ),
          // La même frise que la vue plein écran (voir _FrameTimeline),
          // repliée en bandeau au bas de la case plutôt qu'en ligne à part :
          // une case peut être minuscule, il n'y a pas la place d'une
          // seconde rangée sous la carte comme dans la vue plein écran. Le
          // dégradé fait lire le texte blanc sur n'importe quelle tuile en
          // dessous, précipitations ou pas.
          if (showClock)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fond propre plutôt que de compter sur le seul dégradé
                    // du bandeau : cette ligne est la plus proche du haut de
                    // la case, là où le dégradé est le plus transparent — et
                    // la carte en dessous peut être claire (swisstopo).
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (paused && onResume != null) ...[
                            GestureDetector(
                              onTap: onResume,
                              child: const Icon(Icons.play_arrow, color: Colors.white70, size: 14),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _frameClock(frame),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    _FrameTimeline(
                      frames: catalog.frames,
                      currentFrame: frame,
                      paused: paused,
                      onScrub: onScrub ?? (_) {},
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Combien de tuiles il faut pour couvrir [px] px à [_targetTilePx] chacune
  /// — au moins une, toujours impair (une tuile centrale exacte plutôt qu'une
  /// frontière entre deux). Plafonné large (15 tuiles, 3000 px à
  /// [_targetTilePx]) : la taille de tuile est fixe et non déformée (voir
  /// [_grid]), donc contrairement à une taille dérivée qui s'étirerait pour
  /// remplir la case, un plafond trop bas laisserait une marge vide sur une
  /// grande case plutôt que de simplement demander plus de tuiles. Ce
  /// plafond ne sert donc plus qu'à borner le cas pathologique d'une case
  /// sans contrainte réaliste ([_fallbackPx]), pas les grandes cases
  /// ordinaires — aucune case réelle du tableau de bord n'approche 3000 px.
  static int _coverage(double px) {
    final raw = (px / _targetTilePx).ceil().clamp(1, 15);
    return raw | 1;
  }
}

/// La frise du temps couvert par [frames] — passé récent puis prévision
/// courte, dans l'ordre où [RainviewerClient] les renvoie — avec un repère
/// fixe pour « maintenant » et un curseur qui glisse jusqu'à [currentFrame]
/// à mesure que l'animation avance. Répond à « c'est quand, cette image, par
/// rapport à maintenant ? » d'un coup d'œil plutôt qu'en lisant l'heure.
///
/// **Scrutable** : taper ou glisser dessus fige l'animation ([onScrub]) sur
/// l'image la plus proche du point touché — un arrêt sur image explicite,
/// pas un geste qui se perdrait à la frame suivante de la boucle. [paused]
/// recolore alors le curseur pour le dire.
class _FrameTimeline extends StatelessWidget {
  const _FrameTimeline({
    required this.frames,
    required this.currentFrame,
    required this.onScrub,
    this.paused = false,
  });

  final List<RainviewerFrame> frames;
  final RainviewerFrame currentFrame;

  /// L'index de la frame la plus proche du point touché ou glissé.
  final ValueChanged<int> onScrub;

  final bool paused;

  /// Le vert-bleu des boutons d'action de l'appli (`action_button.dart`) —
  /// le curseur est une commande de lecture au même titre, pas une donnée.
  static const _cursorColor = Color(0xFF006A60);

  /// Ambre plutôt que teal une fois figé : même langage que les autres
  /// états d'alerte de l'appli (radar arrière qui approche) pour dire
  /// « ce n'est pas ce qui se passe maintenant », sans texte.
  static const _pausedColor = Color(0xFFFFA726);

  @override
  Widget build(BuildContext context) {
    final earliest = frames.first.time;
    final latest = frames.last.time;
    final range = (latest - earliest).toDouble();

    double fractionOf(int time) => range <= 0 ? 0 : ((time - earliest) / range).clamp(0.0, 1.0);

    int nearestIndex(double fraction) {
      final targetTime = earliest + fraction * range;
      var closest = 0;
      var closestDelta = (frames[0].time - targetTime).abs();
      for (var i = 1; i < frames.length; i++) {
        final delta = (frames[i].time - targetTime).abs();
        if (delta < closestDelta) {
          closest = i;
          closestDelta = delta;
        }
      }
      return closest;
    }

    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nowFraction = fractionOf(nowSeconds);
    final frameFraction = fractionOf(currentFrame.time);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            void scrubAt(double dx) {
              if (width <= 0) return;
              onScrub(nearestIndex((dx / width).clamp(0.0, 1.0)));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => scrubAt(details.localPosition.dx),
              onHorizontalDragUpdate: (details) => scrubAt(details.localPosition.dx),
              child: SizedBox(
                height: 20,
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // La piste : tout l'intervalle couvert par le catalogue.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 8,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Le passé déjà écoulé, de l'image la plus ancienne à
                    // maintenant — plus clair que la prévision qui suit,
                    // qu'on n'a pas encore vécue.
                    Positioned(
                      left: 0,
                      width: nowFraction * width,
                      top: 8,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Le repère « maintenant » — fixe le temps de l'animation,
                    // il ne bouge qu'au fil des minutes réelles.
                    Positioned(
                      left: (nowFraction * width - 1).clamp(0.0, width - 2),
                      top: 3,
                      child: Container(
                        width: 2,
                        height: 14,
                        color: Colors.white70,
                      ),
                    ),
                    // Le curseur de l'image affichée — glisse d'une frame à
                    // l'autre plutôt que de sauter, pour que l'œil suive
                    // l'animation sur la carte au-dessus sans la chercher.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                      left: (frameFraction * width - 6).clamp(0.0, width - 12),
                      top: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: paused ? _pausedColor : _cursorColor,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _timeLabel(frames.first),
            _timeLabel(frames.last),
          ],
        ),
      ],
    );
  }

  /// L'heure d'une extrémité de la frise, sur un fond propre — la carte en
  /// dessous (`RadarCanvas`) peut très bien être claire (swisstopo est un
  /// fond blanc/gris), et le texte doit rester lisible même là.
  Widget _timeLabel(RainviewerFrame frame) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _frameClock(frame),
          style: const TextStyle(color: Colors.white70, fontSize: 10),
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
  final _mapController = MapController();

  /// Vrai tant que rien n'a déplacé la carte à la main — elle recentre alors
  /// sur chaque nouvelle position GPS, comme une navigation ordinaire.
  /// [onPositionChanged] l'éteint dès qu'un geste (et pas notre propre
  /// [_mapController]) déplace la carte, pour ne pas la ramener sous le
  /// doigt de quelqu'un qui regarde ailleurs ; le bouton de recentrage la
  /// rallume.
  bool _following = true;

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
    _mapController.dispose();
    super.dispose();
  }

  void _recenter(ll.LatLng center) {
    setState(() => _following = true);
    _mapController.move(center, _mapController.camera.zoom);
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

          // En suivi, chaque nouvelle position recentre la carte — après
          // cette frame plutôt que pendant qu'elle se construit, `move`
          // touchant l'arbre de widgets via le contrôleur.
          if (_following) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _following) {
                _mapController.move(center, _mapController.camera.zoom);
              }
            });
          }

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: _initialZoom,
                        minZoom: _minZoom,
                        maxZoom: _maxZoom,
                        onPositionChanged: (camera, hasGesture) {
                          if (hasGesture && _following) setState(() => _following = false);
                        },
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
                              width: 28,
                              height: 28,
                              child: _RiderArrow(headingDeg: fix.headingDeg, size: 28),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Le bouton de recentrage — seulement une fois qu'on
                    // s'est écarté du suivi, sans quoi il n'aurait rien à
                    // faire et resterait juste dans le champ de vision.
                    if (!_following)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: GestureDetector(
                          onTap: () => _recenter(center),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.my_location, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: _FrameTimeline(
                  frames: catalog.frames,
                  currentFrame: frame,
                  paused: _animator.isPaused,
                  onScrub: _animator.seekTo,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Seulement visible en arrêt sur image — reprendre
                        // n'a de sens que là, pas pendant que ça défile déjà.
                        if (_animator.isPaused) ...[
                          GestureDetector(
                            onTap: _animator.resume,
                            child: const Icon(Icons.play_arrow, color: Colors.white70, size: 18),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          '${_frameClock(frame)} · ${_frameCaption(frame)}',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
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
