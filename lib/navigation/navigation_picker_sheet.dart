import 'package:flutter/material.dart';

import '../ui/formats.dart';
import 'navigation_target.dart';
import 'route_catalog_fetch.dart';
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
    this.fetch = const RouteCatalogFetch(),
  });

  final RouteCatalogStore catalog;
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

  @override
  Widget build(BuildContext context) {
    final routes = widget.catalog.routes;

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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.explore),
            title: const Text('Navigation libre'),
            subtitle: const Text('Carte et position, sans itinéraire'),
            onTap: () => _pick(const NavigationTarget.free()),
          ),
          const Divider(),
          _header(),
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

  /// Ce qu'on dit quand la liste est vide — et il y a quatre façons de l'être,
  /// dont une seule que le cycliste puisse corriger.
  Widget _emptyMessage() {
    final message = switch (_status) {
      null => 'Chargement…',
      RouteFetchStatus.signedOut =>
        'Connecte-toi depuis l\'écran Compte pour retrouver tes itinéraires.',
      RouteFetchStatus.failed =>
        'Liste indisponible hors ligne, et rien en mémoire. '
            'Le lien d\'un itinéraire partagé marche quand même.',
      RouteFetchStatus.ok => 'Aucun itinéraire enregistré sur le site.',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _routeTile(RouteSummary route) {
    // Une liste venue du cache peut dater : le dire là où on la lit, sans en
    // faire une alerte — elle reste parfaitement utilisable.
    final stale = _status != null && _status != RouteFetchStatus.ok;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(route.activity)),
      title: Text(route.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${formatDistance(route.distanceM)} · '
        '${route.elevationGainM.round()} m D+'
        '${stale && route.updatedAt != null ? ' · en mémoire' : ''}',
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
