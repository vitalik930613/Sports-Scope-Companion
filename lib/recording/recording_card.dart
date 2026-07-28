import 'package:flutter/material.dart';

import '../ui/formats.dart';
import 'gps_source.dart';
import 'ride_recorder.dart';
import 'ride_store.dart';
import 'rides_page.dart';

/// Le bandeau d'enregistrement : démarrer, mettre en pause, arrêter.
///
/// Posé sur l'écran des capteurs, mais volontairement autonome : il ne sait
/// rien de cet écran, seulement de l'enregistreur. C'est ce qui permettra de le
/// remettre ailleurs (une surcouche sur la navigation, par exemple) sans le
/// réécrire.
class RecordingCard extends StatelessWidget {
  const RecordingCard({super.key, required this.recorder, required this.store});

  final RideRecorder recorder;
  final RideStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) => Card(
        color: recorder.isActive
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: recorder.isActive ? _active(context) : _idle(context),
        ),
      ),
    );
  }

  Widget _idle(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enregistrement',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text('GPS et capteurs, exportable en .fit',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: () => _start(context),
          icon: const Icon(Icons.fiber_manual_record),
          label: const Text('Démarrer'),
        ),
      ],
    );
  }

  Widget _active(BuildContext context) {
    final paused = recorder.state == RecorderState.paused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              paused ? Icons.pause_circle : Icons.fiber_manual_record,
              color: paused ? Colors.orange : Colors.red,
            ),
            const SizedBox(width: 8),
            // Le chronomètre compte les secondes *enregistrées* : en pause il
            // se fige, ce qui est justement l'information qu'on cherche à voir.
            Text(
              formatDuration(recorder.recorded),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Spacer(),
            Text(
              formatDistance(recorder.distanceM),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(_gpsLabel(), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: paused ? recorder.resume : recorder.pause,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                label: Text(paused ? 'Reprendre' : 'Pause'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _stop(context),
                icon: const Icon(Icons.stop),
                label: const Text('Terminer'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Un enregistrement qui tourne sans position accrochée est le piège de ce
  /// genre d'appli : tout a l'air normal, et la trace est vide. On le dit.
  String _gpsLabel() {
    final fix = recorder.lastFix;
    if (fix == null) return 'GPS : en attente d\'une position…';
    final accuracy = fix.accuracyM;
    final age = DateTime.now().difference(fix.at);
    if (age > RideRecorder.fixTtl) {
      return 'GPS : position perdue depuis ${formatDuration(age)}';
    }
    return accuracy == null
        ? 'GPS : accroché'
        : 'GPS : ±${accuracy.round()} m';
  }

  Future<void> _start(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await recorder.start();
    } on GpsUnavailable catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Enregistrement impossible : $e')));
    }
  }

  Future<void> _stop(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final session = await recorder.stop();
    if (session == null) return;

    messenger.showSnackBar(SnackBar(
      content: Text('Sortie enregistrée : ${formatDistance(session.distanceM)} '
          'en ${formatDuration(session.moving)}'),
      action: SnackBarAction(
        label: 'Exporter',
        onPressed: () => navigator.push(MaterialPageRoute(
          builder: (_) => RidesPage(store: store, recorder: recorder),
        )),
      ),
    ));
  }
}
