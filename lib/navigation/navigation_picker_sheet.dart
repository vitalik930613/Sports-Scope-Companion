import 'package:flutter/material.dart';

import '../dashboard/companion_settings_store.dart';
import '../ui/formats.dart';
import 'nav_session.dart';
import 'navigation_target.dart';
import 'route_catalog_fetch.dart';
import '../dashboard/ride_preset.dart';
import 'route_catalog_store.dart';
import 'route_summary.dart';

/// Ce qu'on navigue : un itinéraire du compte, un lien reçu ailleurs, ou rien.
///
/// La feuille **rend une cible** et n'ouvre rien elle-même : ouvrir la
/// navigation demande une permission et peut poser la question de
/// l'enregistrement, deux choses qui n'ont pas leur place dans un sélecteur.
///
/// La liste s'affiche depuis le cache **avant** que le réseau ait répondu. C'est
/// délibéré : le moment où l'on choisit un tracé est le départ, c'est-à-dire
/// souvent un parking de col sans 4G. Attendre le site donnerait une feuille
/// vide deux secondes à chaque fois, et rien du tout là où ça compte.
class NavigationPickerSheet extends StatefulWidget {
  const NavigationPickerSheet({
    super.key,
    required this.catalog,
    this.settings,
    this.fetch = const RouteCatalogFetch(),
  });

  final RouteCatalogStore catalog;

  /// Les profils de sortie, pour choisir celui du jour.
  ///
  /// Facultatif : nul dans les tests, et **la ligne ne paraît pas non plus quand
  /// il n'y a qu'un profil** — un sélecteur à un seul choix est du bruit sur
  /// l'écran d'avant-départ, celui où l'on a encore les mains libres mais pas
  /// l'envie de lire.
  final CompanionSettingsStore? settings;

  final RouteCatalogFetch fetch;

  @override
  State<NavigationPickerSheet> createState() => _NavigationPickerSheetState();
}

class _NavigationPickerSheetState extends State<NavigationPickerSheet> {
  final _link = TextEditingController();

  /// `null` tant que le site n'a pas répondu. Ne dit rien de ce qui est affiché
  /// — le cache, lui, est là dès l'ouverture.
  RouteFetchStatus? _status;
  bool _refreshing = false;
  String? _linkError;

  /// Le tracé que la page de navigation a laissé derrière elle, lu dans son
  /// stockage au rafraîchissement. Rien en cache ici : voir [RouteCatalogFetch].
  NavSessionSummary? _session;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final result = await widget.fetch.run();
    if (result.status == RouteFetchStatus.ok) {
      await widget.catalog.record(result.routes);
    }
    if (!mounted) return;
    setState(() {
      _status = result.status;
      _session = result.session;
      _refreshing = false;
    });
  }

  void _pick(NavigationTarget target) => Navigator.of(context).pop(target);

  void _pickPastedLink() {
    final uri = Uri.tryParse(_link.text.trim());
    final target = uri == null ? null : NavigationTarget.parse(uri);
    if (target == null) {
      setState(() => _linkError = 'Ce lien ne mène pas à un itinéraire.');
      return;
    }
    _pick(target);
  }

  /// Choisir le profil de la sortie.
  ///
  /// Une feuille de plus plutôt qu'un menu déroulant : les profils portent des
  /// noms libres venus du site, et un menu qui déborde de l'écran se manipule
  /// mal avec des gants.
  Future<void> _choosePreset() async {
    final settings = widget.settings;
    if (settings == null) return;

    final key = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final preset in settings.settings.presets)
              ListTile(
                leading: Icon(
                  preset.hasMap ? Icons.map_outlined : Icons.home_outlined,
                ),
                title: Text(preset.name),
                subtitle: Text(_describe(preset)),
                selected: preset.key == settings.preset.key,
                onTap: () => Navigator.of(context).pop(preset.key),
              ),
          ],
        ),
      ),
    );

    if (key == null) return;
    await settings.select(key);
    if (mounted) setState(() {});
  }

  /// Ce qu'un profil change, en une ligne.
  ///
  /// Les capteurs coupés sont **écrits en toutes lettres ici**, parce que c'est
  /// le seul endroit où on les voit : la rangée d'état de l'accueil dit ce que
  /// les appareils font, pas ce qu'un profil demande, et y ajouter un état
  /// visuel de plus ferait trois façons différentes d'être gris.
  static String _describe(RidePreset preset) {
    final off = [
      if (!preset.hasMap) 'sans carte',
      if (!preset.sensors.gps) 'sans GPS',
      if (!preset.sensors.radar) 'sans radar',
    ];
    final count = preset.pages.length;
    final pages = '$count page${count > 1 ? 's' : ''}';
    return off.isEmpty ? pages : '$pages · ${off.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final routes = widget.catalog.routes;
    final settings = widget.settings;
    final preset = settings?.preset;

    // Un profil sans carte n'a aucun itinéraire à choisir : la feuille se réduit
    // au profil et au départ. Proposer « mes itinéraires » à qui roule sur
    // home-trainer ferait chercher une carte qui ne s'ouvrira pas.
    if (preset != null && !preset.hasMap) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _presetTile(),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _pick(const NavigationTarget.free()),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Démarrer la sortie'),
            ),
          ],
        ),
      );
    }

    return Padding(
      // Le clavier quand il est là, la barre de navigation d'Android sinon.
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom +
            16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _presetTile(),
          if (_session != null) _resumeTile(_session!),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.explore),
            title: const Text('Navigation libre'),
            subtitle: const Text('Carte et position, sans itinéraire'),
            onTap: () => _pick(const NavigationTarget.free()),
          ),
          const Divider(),
          _header(),
          _notice(),
          Flexible(
            child: routes.isEmpty
                ? _emptyMessage()
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: routes.length,
                      itemBuilder: (context, i) => _routeTile(routes[i]),
                    ),
                  ),
          ),
          const Divider(),
          TextField(
            controller: _link,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Ou un lien d\'itinéraire partagé',
              hintText: 'https://sports.logicraft.ch/routes/…',
              errorText: _linkError,
            ),
            onChanged: (_) {
              if (_linkError != null) setState(() => _linkError = null);
            },
            onSubmitted: (_) => _pickPastedLink(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _pickPastedLink,
            icon: const Icon(Icons.navigation),
            label: const Text('Naviguer ce lien'),
          ),
        ],
      ),
    );
  }

  /// Le profil de la sortie, en tête de la feuille.
  ///
  /// En tête parce qu'il commande tout le reste — jusqu'à l'existence d'une
  /// carte — et parce que c'est le geste qu'on fait en premier : on choisit son
  /// vélo, puis son itinéraire.
  Widget _presetTile() {
    final settings = widget.settings;
    if (settings == null || !settings.hasChoice) return const SizedBox.shrink();

    final preset = settings.preset;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(preset.hasMap ? Icons.map_outlined : Icons.home_outlined),
      title: Text('Profil : ${preset.name}'),
      subtitle: Text(_describe(preset)),
      trailing: const Icon(Icons.expand_more),
      onTap: _choosePreset,
    );
  }

  /// « Continuer » : le tracé que la page suivait encore il y a peu.
  ///
  /// En tête, et pas au milieu de la liste : rouvrir le sélecteur en pleine
  /// sortie — téléphone rangé, appli revenue à l'accueil — n'a presque jamais
  /// d'autre but que de reprendre là où on en était. Une destination ad hoc
  /// (« naviguer ici ») n'est même joignable que par là : elle n'existe nulle
  /// part côté serveur, donc dans aucune liste.
  Widget _resumeTile(NavSessionSummary session) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.navigation),
      title: const Text('Continuer l\'itinéraire en cours'),
      subtitle: Text(
        session.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _pick(NavigationTarget.resume(label: session.label)),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Mes itinéraires',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (_refreshing)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  /// Ce qui s'est passé au dernier rafraîchissement, quand ce n'est pas « tout
  /// va bien ».
  ///
  /// Affiché **même quand la liste n'est pas vide** : une liste qui date sans le
  /// dire est pire qu'une liste absente, parce qu'on lui fait confiance. Et sur
  /// les deux causes possibles, une seule se corrige — autant ne pas les
  /// confondre.
  Widget _notice() {
    final message = switch (_status) {
      RouteFetchStatus.signedOut =>
        'Pas connecté : ouvre l\'écran Compte pour retrouver tes itinéraires.',
      RouteFetchStatus.failed when widget.catalog.updatedAt != null =>
        'Site injoignable — liste du '
            '${formatDateTime(widget.catalog.updatedAt!)}.',
      RouteFetchStatus.failed => 'Site injoignable.',
      _ => null,
    };

    if (message == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        message,
        style: const TextStyle(color: Colors.orange, fontSize: 12),
      ),
    );
  }

  /// Ce qu'on dit quand la liste est vide. Le cas « pas connecté » et le cas
  /// « injoignable » sont déjà portés par [_notice] : ici on ne traite que ce
  /// qu'il reste.
  Widget _emptyMessage() {
    final message = switch (_status) {
      null => 'Chargement…',
      RouteFetchStatus.ok => 'Aucun itinéraire enregistré sur le site.',
      _ => 'Rien en mémoire. Le lien d\'un itinéraire partagé marche '
          'quand même.',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(message, style: const TextStyle(color: Colors.grey)),
    );
  }

  Widget _routeTile(RouteSummary route) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(route.activity)),
      title: Text(route.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${formatDistance(route.distanceM)} · '
        '${route.elevationGainM.round()} m D+',
      ),
      onTap: () => _pick(
        NavigationTarget(shareToken: route.shareToken, label: route.name),
      ),
    );
  }

  static IconData _iconFor(String? activity) => switch (activity) {
        'cycling' => Icons.directions_bike,
        'mtb' => Icons.terrain,
        'hiking' => Icons.hiking,
        // Le site peut gagner une activité sans que l'appli le sache : une
        // ligne sans pictogramme vaut mieux qu'une ligne absente.
        _ => Icons.route,
      };
}
