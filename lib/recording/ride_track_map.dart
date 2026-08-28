import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../dashboard/block_density.dart';
import '../ride/blocks/block_card.dart';
import '../weather/rainviewer_client.dart' show basemapTileUrlTemplate;
import 'track_point.dart';

/// Le tracé d'une sortie déjà enregistrée, sur le même fond de carte
/// auto-hébergé que le bloc radar précipitations (swisstopo — voir
/// `basemapTileUrlTemplate` pour la couverture et l'attribution requises).
///
/// Non interactive à dessein : elle vit dans le `ListView` d'une page qui
/// doit rester libre de défiler par-dessus. La carte de navigation, elle,
/// négocie le partage du glissé avec `MapSwipeZone` parce qu'elle doit
/// répondre au pincement — ici il n'y a rien à explorer qu'un tracé déjà
/// terminé. Un tap ouvre plutôt une vue plein écran ([_RideTrackDetailPage])
/// où pincer/zoomer a du sens, une fois qu'on n'a plus à partager le geste
/// avec le défilement de la page.
///
/// Suppose une hauteur bornée par l'appelant (`SizedBox`), même contrat que
/// [ElevationProfileSurface] posée dans cette même page.
class RideTrackMap extends StatelessWidget {
  const RideTrackMap({super.key, required this.points});

  final List<TrackPoint> points;

  /// Plafond de sommets dessinés dans l'aperçu. Au-delà, un point de plus par
  /// seconde n'ajoute rien de visible sur une carte de quelques centimètres —
  /// une sortie de 6 h porte 20 000+ points GPS — et `Polyline` ralentit avec
  /// autant de sommets pour un rendu qui, lui, ne dépend que de la forme du
  /// tracé. La vue plein écran ([_RideTrackDetailPage]), elle, garde tous les
  /// points : c'est justement pour distinguer le détail d'un lacet qu'on
  /// zoome.
  static const _previewMaxVertices = 1500;

  @override
  Widget build(BuildContext context) {
    final track = _trackOf(points, maxVertices: _previewMaxVertices);
    // L'appelant décide déjà d'inclure ou non cette carte (même convention
    // que le profil d'altitude) ; ce repli ne sert qu'à ne pas planter un
    // appelant qui l'aurait posée sans vérifier.
    if (track.length < 2) return const SizedBox.shrink();

    final bounds = LatLngBounds.fromPoints(track);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(BlockMetrics.natural.padding),
      decoration: BoxDecoration(
        color: BlockCard.background,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRACÉ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: BlockMetrics.natural.titleSize,
            ),
          ),
          SizedBox(height: BlockMetrics.natural.gap),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _RideTrackDetailPage(points: points),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCameraFit: CameraFit.bounds(
                            bounds: bounds,
                            padding: const EdgeInsets.all(24),
                          ),
                          interactionOptions:
                              const InteractionOptions(flags: InteractiveFlag.none),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: basemapTileUrlTemplate,
                            userAgentPackageName: 'ch.logicraft.sports.companion',
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: track,
                                strokeWidth: 3,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 2,
                      child: Text(
                        '© swisstopo',
                        style: TextStyle(fontSize: 10, color: Colors.black.withValues(alpha: 0.6)),
                      ),
                    ),
                    // Le geste tape sur la carte plutôt que sur un bouton
                    // dédié : rien d'autre à faire ici qu'agrandir, pas
                    // besoin de disputer la place à une icône.
                    const Positioned(
                      left: 6,
                      top: 2,
                      child: _ExpandHint(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Les positions de [points], en `LatLng`, décimées à [maxVertices] par un
  /// pas régulier si besoin — jamais autrement (pas de simplification de
  /// forme façon Douglas-Peucker) : plus simple, et suffisant vu la densité
  /// d'un point par seconde.
  static List<ll.LatLng> _trackOf(List<TrackPoint> points, {int? maxVertices}) {
    final withPosition = [
      for (final point in points)
        if (point.hasPosition) point,
    ];

    if (maxVertices == null || withPosition.length <= maxVertices) {
      return [for (final point in withPosition) ll.LatLng(point.lat!, point.lng!)];
    }

    final stride = (withPosition.length / maxVertices).ceil();
    return [
      for (var i = 0; i < withPosition.length; i += stride)
        ll.LatLng(withPosition[i].lat!, withPosition[i].lng!),
    ];
  }
}

/// Un petit repère « agrandir » sur l'aperçu — sans lui, rien ne dit qu'une
/// carte qui ne répond déjà à aucun pincement/glissé répond quand même à un
/// tap.
class _ExpandHint extends StatelessWidget {
  const _ExpandHint();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 16),
      );
}

/// La vue plein écran ouverte au tap sur [RideTrackMap] : le même tracé, en
/// entier (pas de décimation — voir [RideTrackMap._previewMaxVertices]), sur
/// une carte librement interactive puisqu'elle n'a plus de défilement de page
/// à ménager. Même patron que la vue plein écran du bloc radar précipitations
/// (`_PrecipRadarDetailPage`), sans le suivi de position live que celle-là
/// gère en plus : ici le tracé est figé, il n'y a qu'à le regarder.
class _RideTrackDetailPage extends StatefulWidget {
  const _RideTrackDetailPage({required this.points});

  final List<TrackPoint> points;

  @override
  State<_RideTrackDetailPage> createState() => _RideTrackDetailPageState();
}

class _RideTrackDetailPageState extends State<_RideTrackDetailPage> {
  final _mapController = MapController();
  late final List<ll.LatLng> _track =
      RideTrackMap._trackOf(widget.points);
  late final LatLngBounds _bounds = LatLngBounds.fromPoints(_track);

  static const _boundsPadding = EdgeInsets.all(32);

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _fitToTrack() {
    _mapController.fitCamera(CameraFit.bounds(bounds: _bounds, padding: _boundsPadding));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Tracé'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(bounds: _bounds, padding: _boundsPadding),
            ),
            children: [
              TileLayer(
                urlTemplate: basemapTileUrlTemplate,
                userAgentPackageName: 'ch.logicraft.sports.companion',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _track,
                    strokeWidth: 4,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: GestureDetector(
              onTap: _fitToTrack,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fit_screen, color: Colors.white, size: 20),
              ),
            ),
          ),
          const Positioned(
            left: 12,
            bottom: 12,
            child: Text(
              '© swisstopo',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
