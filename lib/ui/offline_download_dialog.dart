import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ride/offline_map_state.dart';

/// Ouvre la carte hors-ligne du trajet affiché : choisir les fonds, télécharger,
/// suivre la progression, supprimer.
///
/// Le téléchargement lui-même (tuiles, archive PMTiles) reste entièrement côté
/// site — voir `OfflineMapNotifier` et `companionBridge.ts` du dépôt Rails.
/// Cette boîte n'est qu'une vue sur son état : elle compose les gestes que le
/// panneau web propose déjà en navigateur, panneau lui-même masqué dans l'appli.
Future<void> showOfflineDownloadDialog(
  BuildContext context, {
  required ValueListenable<OfflineMapState?> state,
  required VoidCallback start,
  required VoidCallback cancel,
  required VoidCallback remove,
  required ValueChanged<String> toggleLayer,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => OfflineDownloadDialog(
      state: state,
      start: start,
      cancel: cancel,
      remove: remove,
      toggleLayer: toggleLayer,
    ),
  );
}

class OfflineDownloadDialog extends StatelessWidget {
  const OfflineDownloadDialog({
    super.key,
    required this.state,
    required this.start,
    required this.cancel,
    required this.remove,
    required this.toggleLayer,
  });

  final ValueListenable<OfflineMapState?> state;
  final VoidCallback start;
  final VoidCallback cancel;
  final VoidCallback remove;
  final ValueChanged<String> toggleLayer;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfflineMapState?>(
      valueListenable: state,
      builder: (context, value, _) => AlertDialog(
        title: const Text('Carte hors ligne'),
        content: SizedBox(
          width: double.maxFinite,
          child: _content(value),
        ),
        actions: _actions(context, value),
      ),
    );
  }

  Widget _content(OfflineMapState? value) {
    if (value == null || !value.supported) {
      return const Text(
        'Rien à archiver ici : reviens sur la carte, avec un itinéraire '
        'suivi.',
      );
    }
    if (value.downloading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: value.pct / 100),
          const SizedBox(height: 8),
          Text('${value.pct} %'),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Absent contre un site plus ancien que ce réglage (avant les fonds IGN) :
        // la boîte replie alors sur le fond déjà actif, comme avant lui.
        if (value.layers.isNotEmpty) ..._layerTiles(value),
        _statusLine(value),
      ],
    );
  }

  /// Une case à cocher par fond archivable — même geste que le panneau web,
  /// relayé par `toggleLayer`. `ready`/`stale` en petite pastille : le trajet
  /// peut avoir une archive à jour pour l'un et périmée pour l'autre.
  List<Widget> _layerTiles(OfflineMapState value) {
    return [
      for (final layer in value.layers)
        CheckboxListTile(
          value: layer.selected,
          onChanged: (_) => toggleLayer(layer.id),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(layer.label),
          secondary: layer.stale
              ? const Icon(Icons.autorenew, color: Colors.orange)
              : layer.ready
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
        ),
      const SizedBox(height: 4),
    ];
  }

  Widget _statusLine(OfflineMapState value) {
    if (value.errored) {
      return const Text(
        'Le téléchargement a échoué. Vérifie le réseau, puis réessaie.',
      );
    }
    if (value.stale) {
      return const Text(
        'Le tracé a changé depuis le téléchargement (reroutage, détour) : la '
        'carte hors ligne ne couvre plus tout l\'itinéraire.',
      );
    }
    if (value.ready) {
      return const Text('La carte de ce trajet est prête pour la route.');
    }
    if (value.layers.isNotEmpty && !value.layers.any((l) => l.selected)) {
      return const Text('Choisis au moins un fond.');
    }
    return Text(
      value.mb > 0
          ? '~${value.mb.toStringAsFixed(0)} Mo, ${value.tiles} tuiles, '
              'autour du tracé.'
          : 'Calcul de la taille…',
    );
  }

  List<Widget> _actions(BuildContext context, OfflineMapState? value) {
    final close = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Fermer'),
    );
    if (value == null || !value.supported) return [close];

    if (value.downloading) {
      return [
        close,
        FilledButton(onPressed: cancel, child: const Text('Annuler')),
      ];
    }

    final needsDownload = !value.ready || value.stale;
    // Rien de coché ne doit pas pouvoir se lancer — même garde que le bouton
    // du panneau web (`offlineNothingSelected`). Absent des layers (site plus
    // ancien) : toujours vrai, comme avant ce réglage.
    final nothingSelected =
        value.layers.isNotEmpty && !value.layers.any((l) => l.selected);
    return [
      if (value.ready)
        TextButton(onPressed: remove, child: const Text('Supprimer')),
      close,
      if (needsDownload)
        FilledButton(
          onPressed: nothingSelected ? null : start,
          child: Text(value.stale ? 'Mettre à jour' : 'Télécharger'),
        ),
    ];
  }
}
