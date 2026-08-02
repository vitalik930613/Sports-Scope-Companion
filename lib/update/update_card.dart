import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'companion_release.dart';
import 'update_checker.dart';

/// « Une version plus récente existe », sur l'écran d'accueil.
///
/// Sa place est ici et pas dans une notification : l'appli se diffuse hors Play
/// Store, personne ne la met à jour à sa place, et l'écran d'avant-départ est le
/// seul moment où le cycliste a les mains libres pour installer 19 Mo. Même
/// raisonnement que `ThresholdGap` — on annonce le trou là où il peut encore se
/// combler.
///
/// Discrète par construction : rien tant qu'il n'y a rien à dire (hors ligne, à
/// jour, contrôle échoué), et jamais de boîte qui barre la route vers
/// « Naviguer ».
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.checker});

  final UpdateChecker checker;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: checker,
      builder: (context, _) {
        final release = checker.available;
        if (release == null) return const SizedBox.shrink();

        return Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: ListTile(
            leading: const Icon(Icons.system_update),
            title: Text('Version ${release.versionName} disponible'),
            subtitle: Text(_subtitle(release)),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _open(context, release),
          ),
        );
      },
    );
  }

  String _subtitle(CompanionRelease release) {
    final size = release.size;
    if (size == null) return 'Se télécharge depuis le site.';
    // Mêmes mégaoctets que la page du site (`number_to_human_size`, base 1024) :
    // deux conventions donneraient 18 ici et 19 là pour un seul fichier, de quoi
    // se demander lequel on télécharge.
    final mb = (size / (1024 * 1024)).toStringAsFixed(1);
    return 'Se télécharge depuis le site · $mb Mo';
  }

  Future<void> _open(BuildContext context, CompanionRelease release) async {
    // `externalApplication` : la page demande une session, et c'est Chrome qui
    // la détient (le pot de cookies des WebViews de l'appli est un autre pot).
    // C'est aussi Chrome qui enchaîne le téléchargement sur l'installateur.
    final opened = await launchUrl(
      Uri.parse(release.downloadUrl),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ouvre ${release.downloadUrl} dans ton navigateur')),
    );
  }
}
