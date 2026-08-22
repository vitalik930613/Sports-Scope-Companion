import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../account/rider_profile_store.dart';
import '../ui/formats.dart';
import 'fit_writer.dart';
import 'ride_detail_page.dart';
import 'ride_recorder.dart';
import 'ride_session.dart';
import 'ride_store.dart';
import 'ride_upload.dart';

/// Les sorties enregistrées : ce qu'on a, et comment le sortir de l'appli.
///
/// L'export produit un `.fit` puis passe la main au partage d'Android — le
/// chemin le plus bête pour en faire quelque chose ailleurs (PC, mail, un
/// autre site). L'envoi direct, lui, ne construit ni ne partage aucun
/// fichier : il pousse la sortie vers `/api/imported_activities` par un
/// WebView hors écran (`RideUploadFetch`), exactement comme la lecture du
/// catalogue d'itinéraires — la session est le cookie du pot partagé des
/// WebViews, jamais un jeton que l'appli devrait conserver de son côté.
class RidesPage extends StatefulWidget {
  const RidesPage({
    super.key,
    required this.store,
    required this.recorder,
    required this.riderProfile,
  });

  final RideStore store;

  /// L'enregistreur, seulement pour reconnaître la sortie en cours : elle
  /// s'affiche, mais ne s'exporte ni ne se supprime tant qu'elle écrit.
  final RideRecorder recorder;

  /// Transmis tel quel à l'écran de détail, pour ses zones et son TSS.
  final RiderProfileStore riderProfile;

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

  /// Les sorties qu'un « tout supprimer » emporterait : jamais celle en cours,
  /// même règle que la suppression individuelle (menu désactivé sur sa tuile).
  List<RideSession> _deletable(List<RideSession> sessions) =>
      sessions.where((s) => !_isActive(s)).toList();

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

  /// Envoie la sortie directement à sports-scope, sans passer par un fichier.
  ///
  /// Même sélecteur de sport que l'export : l'appli ne sait toujours pas ce
  /// qu'on a roulé, seulement les capteurs et le GPS.
  Future<void> _upload(RideSession session) async {
    final sport = await _pickSport();
    if (sport == null) return;

    setState(() => _busyId = session.id);
    try {
      final points = await widget.store.points(session.id);
      final payload =
          buildRideUploadPayload(session: session, points: points, sport: sport);
      final result = await const RideUploadFetch().run(payload);
      switch (result.status) {
        case RideUploadStatus.ok:
          _toast('Sortie envoyée sur sports-scope.');
        case RideUploadStatus.signedOut:
          _toast('Connecte-toi sur sports-scope (onglet Compte) avant d\'envoyer.');
        case RideUploadStatus.failed:
          _toast('Envoi impossible${result.message != null ? ' : ${result.message}' : ', réessaie plus tard'}.');
      }
    } on EmptyRide {
      _toast('Cette sortie n\'a aucun point enregistré.');
    } catch (e) {
      _toast('Envoi impossible : $e');
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
            _sportOption(dialogContext, FitSport.cycling, Icons.directions_bike),
            _sportOption(dialogContext, FitSport.mtb, Icons.terrain),
            _sportOption(dialogContext, FitSport.hiking, Icons.hiking),
          ],
        ),
      );

  Widget _sportOption(
    BuildContext dialogContext,
    FitSport sport,
    IconData icon,
  ) =>
      SimpleDialogOption(
        onPressed: () => Navigator.of(dialogContext).pop(sport),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Text(sport.label),
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

  Future<void> _deleteAll() async {
    final deletable = _deletable(_sessions ?? const []);
    if (deletable.isEmpty) return;

    final count = deletable.length;
    final noun = count > 1 ? 'sorties' : 'sortie';
    final verb = count > 1 ? 'seront perdues' : 'sera perdue';
    final keepsActive = deletable.length != (_sessions?.length ?? 0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer toutes les sorties ?'),
        content: Text(
          '$count $noun $verb. Pense à exporter celles qui comptent avant.'
          '${keepsActive ? '\n\nLa sortie en cours n\'est pas concernée.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Tout supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final session in deletable) {
      await widget.store.delete(session.id);
    }
    await _reload();
  }

  /// Ouvre le détail d'une sortie — bilan, profil d'altitude, zones, tours.
  /// Sans garde particulière au-delà de ça : c'est une lecture seule, sans
  /// le risque qui justifie `enabled: !active` sur le menu export/suppression.
  void _openDetail(RideSession session) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RideDetailPage(
        session: session,
        store: widget.store,
        riderProfile: widget.riderProfile,
      ),
    ));
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
            onPressed:
                _deletable(sessions ?? const []).isEmpty ? null : _deleteAll,
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Tout supprimer',
          ),
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
      onTap: () => _openDetail(session),
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
                'upload' => _upload(session),
                'export' => _export(session),
                'delete' => _delete(session),
                _ => null,
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'upload',
                  enabled: session.pointCount > 0,
                  child: const Text('Envoyer à sports-scope'),
                ),
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
