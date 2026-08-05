import 'package:flutter/foundation.dart';

/// Ce que la page de navigation dit de la carte hors-ligne du trajet affiché.
///
/// Le téléchargement lui-même (choix des fonds, tuiles, archive PMTiles dans
/// l'OPFS) reste entièrement côté site — voir `useOfflineMaps.ts` et
/// `companionBridge.ts` du dépôt Rails. L'appli ne fait que déclencher les
/// trois gestes que le panneau web propose déjà (démarrer, annuler, supprimer)
/// et afficher où ça en est, dans son propre menu — le panneau web, lui, est
/// masqué dans l'appli (`appOwnsChrome`).
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

  static OfflineMapState? fromJson(Map<dynamic, dynamic> json) {
    if (json['type'] != 'offline') return null;
    return OfflineMapState(
      supported: json['supported'] == true,
      ready: json['ready'] == true,
      stale: json['stale'] == true,
      downloading: json['downloading'] == true,
      pct: json['pct'] is num ? (json['pct'] as num).toInt() : 0,
      mb: json['mb'] is num ? (json['mb'] as num).toDouble() : 0,
      tiles: json['tiles'] is num ? (json['tiles'] as num).toInt() : 0,
      errored: json['errored'] == true,
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
