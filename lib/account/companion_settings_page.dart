import 'package:flutter/material.dart';

import '../dashboard/companion_settings_store.dart';
import 'companion_settings_write.dart';
import 'map_style_write.dart';

/// Réglages globaux du compte (pas ceux d'un profil de sortie) : deviner un col
/// en navigation libre, et le fond de carte de la navigation guidée.
///
/// **Écrit par l'appli elle-même**, pas seulement par l'éditeur web — voir
/// `CompanionSettingsWrite` (document complet, fusionné côté site) et
/// `MapStyleWrite` (un seul champ, fusionné côté serveur) ; seul autre
/// précédent d'écriture depuis Dart : `RideUploadFetch`.
///
/// Le fond de carte vit ici et non dans la coquille de sortie
/// (`RideShellPage`) : `NavControlsPanel`, qui le propose en navigateur, est
/// masqué dans l'appli tout du long d'une sortie (`appOwnsChrome`) — il n'y a
/// donc nulle part où le choisir *pendant* la navigation, seulement avant de
/// partir.
class CompanionSettingsPage extends StatefulWidget {
  const CompanionSettingsPage({super.key, required this.settings});

  final CompanionSettingsStore settings;

  @override
  State<CompanionSettingsPage> createState() => _CompanionSettingsPageState();
}

class _CompanionSettingsPageState extends State<CompanionSettingsPage> {
  bool _saving = false;

  Future<void> _setColDetection(bool value) async {
    // Le document brut du compte, PAS un document reconstruit : `sanitize` côté
    // site remplacerait tout par les préréglages d'usine si `presets` manquait.
    final document = widget.settings.rawDocument;
    if (document == null) {
      _snack('Aucun réglage reçu du site pour l\'instant — connecte-toi '
          '(bouton Compte) et réessaie.');
      return;
    }

    setState(() => _saving = true);
    final result = await const CompanionSettingsWrite().run({
      ...document,
      'col_detection': value,
    });
    if (!mounted) return;
    setState(() => _saving = false);

    switch (result.status) {
      case CompanionSettingsWriteStatus.ok:
        // Le document RENVOYÉ (assaini par le serveur), pas celui envoyé — même
        // contrat que l'éditeur web.
        await widget.settings.record(result.document);
      case CompanionSettingsWriteStatus.signedOut:
        _snack('Connecte-toi (bouton Compte) pour changer ce réglage.');
      case CompanionSettingsWriteStatus.failed:
        _snack('Échec de l\'enregistrement — réessaie avec du réseau.');
    }
  }

  /// Ouvre le fond de carte choisi. La liste vient du document en cache —
  /// vide contre un site plus ancien que ce réglage — auquel cas on le dit
  /// plutôt que d'ouvrir une boîte sans rien dedans.
  Future<void> _pickMapStyle() async {
    final styles = widget.settings.mapStyles;
    if (styles.isEmpty) {
      _snack('Réglage pas encore disponible — connecte-toi (bouton Compte) '
          'et relance l\'appli.');
      return;
    }

    final current = widget.settings.mapStyle;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Fond de carte de navigation'),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (id) => Navigator.of(context).pop(id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final style in styles)
                  RadioListTile<String>(value: style.id, title: Text(style.label)),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen == null || chosen == current) return;
    await _setMapStyle(chosen);
  }

  Future<void> _setMapStyle(String id) async {
    setState(() => _saving = true);
    final result = await const MapStyleWrite().run(id);
    if (!mounted) return;
    setState(() => _saving = false);

    switch (result.status) {
      case MapStyleWriteStatus.ok:
        // Le fond RENVOYÉ (celui que le serveur a retenu), pas celui envoyé —
        // même contrat que le document complet de CompanionSettingsWrite.
        if (result.id != null) await widget.settings.recordMapStyle(result.id!);
      case MapStyleWriteStatus.signedOut:
        _snack('Connecte-toi (bouton Compte) pour changer ce réglage.');
      case MapStyleWriteStatus.failed:
        _snack('Échec de l\'enregistrement — réessaie avec du réseau.');
    }
  }

  /// Libellé affiché sous la ligne « Fond de carte ». Repli sur l'id brut si
  /// le catalogue ne le connaît pas encore (document tout juste arrivé, une
  /// version plus récente du site a ajouté ce fond) plutôt que de le taire.
  String _mapStyleLabel() {
    final id = widget.settings.mapStyle;
    if (id == null) return 'Pas encore reçu du site';
    for (final style in widget.settings.mapStyles) {
      if (style.id == id) return style.label;
    }
    return id;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              title: const Text('Détection de col en navigation libre'),
              subtitle: const Text(
                'En roulant sans itinéraire, devine — d\'après la pente et les '
                'cols connus alentour — que tu montes vers un col, et te '
                'l\'annonce brièvement.',
              ),
              value: widget.settings.colDetection,
              onChanged: _saving ? null : _setColDetection,
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Fond de carte de navigation'),
              subtitle: Text(_mapStyleLabel()),
              onTap: _saving ? null : _pickMapStyle,
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
