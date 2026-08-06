import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ui/formats.dart';
import 'fit_writer.dart';
import 'ride_recorder.dart';
import 'ride_session.dart';
import 'ride_store.dart';

/// Les sorties enregistrées : ce qu'on a, et comment le sortir de l'appli.
///
/// L'export produit un `.fit` puis passe la main au partage d'Android. C'est
/// volontairement le chemin le plus bête : de là, le fichier part vers le PC,
/// un mail ou un espace de stockage, et se dépose dans la page d'import de
/// sports-scope. Un téléversement direct supposerait de tenir une session
/// authentifiée hors du WebView, pour un gain nul sur la route.
class RidesPage extends StatefulWidget {
  const RidesPage({super.key, required this.store, required this.recorder});

  final RideStore store;

  /// L'enregistreur, seulement pour reconnaître la sortie en cours : elle
  /// s'affiche, mais ne s'exporte ni ne se supprime tant qu'elle écrit.
  final RideRecorder recorder;

  @override
  State<RidesPage> createState() => _RidesPageState();
}

class _RidesPageState extends State<RidesPage> {
  List<RideSession>? _sessions;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sessions = await widget.store.list();
    if (mounted) setState(() => _sessions = sessions);
  }

  bool _isActive(RideSession session) =>
      widget.recorder.session?.id == session.id;

  /// Construit le `.fit` puis ouvre le partage d'Android.
  ///
  /// Le fichier est écrit dans le dossier temporaire : c'est une copie
  /// jetable — la source reste le JSONL de la sortie, qu'on peut réexporter
  /// autant de fois qu'on veut.
  Future<void> _export(RideSession session) async {
    final sport = await _pickSport();
    if (sport == null) return;

    setState(() => _busyId = session.id);
    try {
      final points = await widget.store.points(session.id);
      final bytes = FitWriter.build(session: session, points: points, sport: sport);

      final directory = await getTemporaryDirectory();
      final file = File(p.join(directory.path, FitWriter.fileName(session)));
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      // La position d'origine ne sert qu'aux tablettes iPad ; sur Android elle
      // est ignorée.
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        fileNameOverrides: [FitWriter.fileName(session)],
        subject: 'Sortie du ${formatDateTime(session.startedAt)}',
      ));
    } on EmptyRide {
      _toast('Cette sortie n\'a aucun point enregistré.');
    } catch (e) {
      _toast('Export impossible : $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Ce que la sortie était vraiment, pour le `.fit` — l'appli ne l'a jamais su
  /// pendant l'enregistrement (voir `FitSport`). `null` si l'utilisateur ferme
  /// la boîte sans choisir, ce qui annule l'export plutôt que de deviner.
  Future<FitSport?> _pickSport() => showDialog<FitSport>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Sport de cette sortie'),
          children: [
            _sportOption(dialogContext, FitSport.cycling, Icons.directions_bike, 'Vélo'),
            _sportOption(dialogContext, FitSport.mtb, Icons.terrain, 'VTT'),
            _sportOption(dialogContext, FitSport.hiking, Icons.hiking, 'Randonnée'),
          ],
        ),
      );

  Widget _sportOption(
    BuildContext dialogContext,
    FitSport sport,
    IconData icon,
    String label,
  ) =>
      SimpleDialogOption(
        onPressed: () => Navigator.of(dialogContext).pop(sport),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      );

  Future<void> _delete(RideSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer la sortie ?'),
        content: Text(
          'La trace du ${formatDateTime(session.startedAt)} sera perdue. '
          'Pense à l\'exporter d\'abord si elle compte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.store.delete(session.id);
    await _reload();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => _screen(context);

  Widget _screen(BuildContext context) {
    final sessions = _sessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes sorties'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
          ),
        ],
      ),
      body: switch (sessions) {
        null => const Center(child: CircularProgressIndicator()),
        [] => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Aucune sortie enregistrée pour l\'instant.\n'
                'Démarre un enregistrement depuis l\'écran des capteurs.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        _ => RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _tile(sessions[index]),
            ),
          ),
      },
    );
  }

  Widget _tile(RideSession session) {
    final active = _isActive(session);
    final busy = _busyId == session.id;

    return ListTile(
      leading: Icon(
        active ? Icons.fiber_manual_record : Icons.route,
        color: active ? Colors.red : null,
      ),
      title: Text(formatDateTime(session.startedAt)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${formatDuration(session.moving)} · '
              '${formatDistance(session.distanceM)} · '
              '${session.pointCount} points'),
          if (active)
            const Text('enregistrement en cours',
                style: TextStyle(color: Colors.red))
          // Une sortie sans fin déclarée a été coupée net (batterie, crash) :
          // ses points restent exportables, mais le dire évite de croire que
          // l'appli a perdu la fin du parcours.
          else if (!session.isFinished)
            const Text('interrompue — exportable telle quelle',
                style: TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
      isThreeLine: active || !session.isFinished,
      trailing: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<String>(
              enabled: !active,
              onSelected: (action) => switch (action) {
                'export' => _export(session),
                'delete' => _delete(session),
                _ => null,
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'export',
                  enabled: session.pointCount > 0,
                  child: const Text('Exporter en .fit'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
    );
  }
}
