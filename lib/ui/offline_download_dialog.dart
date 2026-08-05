import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ride/offline_map_state.dart';

/// Ouvre la carte hors-ligne du trajet affiché : télécharger, suivre la
/// progression, supprimer.
///
/// Le téléchargement lui-même (choix des fonds, tuiles, archive PMTiles) reste
/// entièrement côté site — voir `OfflineMapNotifier` et `companionBridge.ts`
/// du dépôt Rails. Cette boîte n'est qu'une vue sur son état : elle compose les
/// trois gestes que le panneau web propose déjà en navigateur, panneau
/// lui-même masqué dans l'appli.
Future<void> showOfflineDownloadDialog(
  BuildContext context, {
  required ValueListenable<OfflineMapState?> state,
  required VoidCallback start,
  required VoidCallback cancel,
  required VoidCallback remove,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => OfflineDownloadDialog(
      state: state,
      start: start,
      cancel: cancel,
      remove: remove,
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
  });

  final ValueListenable<OfflineMapState?> state;
  final VoidCallback start;
  final VoidCallback cancel;
  final VoidCallback remove;

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
    return Text(
      value.mb > 0
          ? '~${value.mb.toStringAsFixed(0)} Mo, ${value.tiles} tuiles — '
              'fond de carte actuel, autour du tracé.'
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
    return [
      if (value.ready)
        TextButton(onPressed: remove, child: const Text('Supprimer')),
      close,
      if (needsDownload)
        FilledButton(
          onPressed: start,
          child: Text(value.stale ? 'Mettre à jour' : 'Télécharger'),
        ),
    ];
  }
}
