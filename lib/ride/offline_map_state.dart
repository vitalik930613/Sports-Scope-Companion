import 'package:flutter/foundation.dart';

/// Une couche archivable (swisstopo gris/couleur/satellite, IGN plan/ortho…), telle que
/// `companionBridge.ts` la décrit. `label` arrive déjà traduite par le site : l'appli n'a
/// pas sa propre table de libellés par id, donc un fond de plus côté site s'affiche
/// correctement ici sans mise à jour de l'appli.
@immutable
class OfflineMapLayer {
  const OfflineMapLayer({
    required this.id,
    required this.label,
    required this.ready,
    required this.stale,
    required this.selected,
  });

  final String id;
  final String label;
  final bool ready;
  final bool stale;
  final bool selected;

  static OfflineMapLayer? parse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    if (id is! String || id.isEmpty) return null;
    return OfflineMapLayer(
      id: id,
      // Repli sur l'id : un site plus ancien que `label` (avant ce réglage) ne
      // doit pas afficher une ligne vide.
      label: label is String && label.isNotEmpty ? label : id,
      ready: raw['ready'] == true,
      stale: raw['stale'] == true,
      selected: raw['selected'] == true,
    );
  }
}

/// Ce que la page de navigation dit de la carte hors-ligne du trajet affiché.
///
/// Le téléchargement lui-même (tuiles, archive PMTiles dans l'OPFS) reste entièrement
/// côté site — voir `useOfflineMaps.ts` et `companionBridge.ts` du dépôt Rails. L'appli
/// ne fait que déclencher les gestes que le panneau web propose déjà (démarrer, annuler,
/// supprimer, cocher une couche) et afficher où ça en est, dans son propre menu — le
/// panneau web, lui, est masqué dans l'appli (`appOwnsChrome`).
@immutable
class OfflineMapState {
  const OfflineMapState({
    required this.supported,
    required this.ready,
    required this.stale,
    required this.downloading,
    required this.pct,
    required this.mb,
    required this.tiles,
    required this.errored,
    required this.layers,
  });

  /// Faux hors itinéraire (rien à archiver) ou contre une page trop ancienne
  /// pour connaître ce message : dans les deux cas, la commande ne doit pas
  /// paraître dans le menu.
  final bool supported;

  /// Une archive couvre déjà le tracé affiché.
  final bool ready;

  /// L'archive existe mais le tracé a changé depuis (reroutage, détour) : elle
  /// ne couvre plus tout l'itinéraire.
  final bool stale;

  final bool downloading;
  final int pct;

  /// Estimation avant téléchargement (fonds sélectionnés côté site) ; sans
  /// valeur une fois l'archive prête.
  final double mb;
  final int tiles;

  final bool errored;

  /// Les fonds archivables et leur sélection courante. Vide contre un site plus ancien
  /// que ce réglage — la boîte replie alors sur son texte d'avant (fond actif, implicite).
  final List<OfflineMapLayer> layers;

  static OfflineMapState? fromJson(Map<dynamic, dynamic> json) {
    if (json['type'] != 'offline') return null;
    final rawLayers = json['layers'];
    return OfflineMapState(
      supported: json['supported'] == true,
      ready: json['ready'] == true,
      stale: json['stale'] == true,
      downloading: json['downloading'] == true,
      pct: json['pct'] is num ? (json['pct'] as num).toInt() : 0,
      mb: json['mb'] is num ? (json['mb'] as num).toDouble() : 0,
      tiles: json['tiles'] is num ? (json['tiles'] as num).toInt() : 0,
      errored: json['errored'] == true,
      layers: rawLayers is List
          ? rawLayers.map(OfflineMapLayer.parse).whereType<OfflineMapLayer>().toList()
          : const [],
    );
  }
}

/// L'état hors-ligne courant, à écouter comme n'importe quelle mesure venue du
/// pont.
class OfflineMapNotifier extends ValueNotifier<OfflineMapState?> {
  OfflineMapNotifier() : super(null);

  /// Range un message venu de la page. Un message illisible est ignoré : on
  /// garde le dernier état valable plutôt que de faire disparaître la commande.
  void accept(Map<dynamic, dynamic> json) {
    final next = OfflineMapState.fromJson(json);
    if (next != null) value = next;
  }

  void reset() => value = null;
}
