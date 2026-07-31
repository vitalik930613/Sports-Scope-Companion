import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/navigation/nav_session.dart';
import 'package:sports_scope_companion/navigation/navigation_picker_sheet.dart';
import 'package:sports_scope_companion/navigation/navigation_target.dart';
import 'package:sports_scope_companion/navigation/route_catalog_fetch.dart';
import 'package:sports_scope_companion/navigation/route_catalog_store.dart';
import 'package:sports_scope_companion/navigation/route_summary.dart';

/// Ce que rend le sélecteur, et rien d'autre : il ne fait qu'énoncer une cible,
/// c'est `openNavigation` qui l'ouvre.
///
/// Le vrai [RouteCatalogFetch] monte un WebView — hors de portée d'un test
/// unitaire, et sans intérêt ici : ce qui se joue, c'est ce que le sélecteur
/// fait de la réponse.
class _StubFetch extends RouteCatalogFetch {
  const _StubFetch(this.result);

  final RouteFetchResult result;

  @override
  Future<RouteFetchResult> run() async => result;
}

/// Un catalogue qui n'écrit rien.
///
/// Le temps est simulé dans un `testWidgets` : une écriture disque **lancée par
/// le widget** n'aboutit jamais, et `runAsync` n'y peut rien — il ne rattrape
/// que ce qu'on démarre soi-même. Le rafraîchissement resterait en cours pour
/// toujours, roue comprise, et `pumpAndSettle` expirerait. La persistance a son
/// propre test (`route_catalog_store_test.dart`), là où elle a un sens.
class _MemoryCatalog extends RouteCatalogStore {
  _MemoryCatalog() : super(File('/jamais-ecrit/route_catalog.json'));

  @override
  Future<void> record(List<RouteSummary> routes) async {}
}

void main() {
  final session = NavSessionSummary(
    name: 'Col de la Croix',
    token: 'abc123',
    savedAt: DateTime.now(),
  );

  final catalog = _MemoryCatalog();

  /// Ouvre la feuille et rend de quoi lire la cible choisie — qui n'arrive
  /// qu'à la fermeture, une fois la sélection faite.
  Future<ValueNotifier<NavigationTarget?>> open(
    WidgetTester tester,
    RouteFetchResult result,
  ) async {
    final picked = ValueNotifier<NavigationTarget?>(null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked.value = await showModalBottomSheet<NavigationTarget>(
                context: context,
                // Comme à l'écran des capteurs : sans ça, la feuille est bornée
                // à la moitié de la hauteur et déborde avant qu'on ait rien
                // vérifié.
                isScrollControlled: true,
                builder: (_) => NavigationPickerSheet(
                  catalog: catalog,
                  fetch: _StubFetch(result),
                ),
              );
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('« Navigation libre » repart à neuf', (tester) async {
    final picked = await open(tester, const RouteFetchResult(
      RouteFetchStatus.ok,
    ));

    await tester.tap(find.text('Navigation libre'));
    await tester.pumpAndSettle();

    // La régression corrigée : sans `fresh`, la page restaure le tracé de sa
    // dernière séance, et « libre » rouvrait l'itinéraire de tout à l'heure.
    expect(picked.value!.resume, isFalse);
    expect(
      picked.value!.url(baseUrl: 'https://sports.logicraft.ch')
          .queryParameters['fresh'],
      '1',
    );
  });

  testWidgets('sans tracé en cours, rien à continuer', (tester) async {
    await open(tester, const RouteFetchResult(RouteFetchStatus.ok));

    expect(find.textContaining('Continuer'), findsNothing);
  });

  testWidgets('un tracé en cours se reprend, nommé et en tête', (tester) async {
    await open(
      tester,
      RouteFetchResult(RouteFetchStatus.ok, const [], session),
    );

    final resume = find.text('Continuer l\'itinéraire en cours');
    expect(resume, findsOneWidget);
    expect(find.text('Col de la Croix'), findsOneWidget);

    // En tête : rouvrir le sélecteur en pleine sortie n'a presque jamais
    // d'autre but que de reprendre là où on en était.
    expect(
      tester.getTopLeft(resume).dy,
      lessThan(tester.getTopLeft(find.text('Navigation libre')).dy),
    );
  });

  testWidgets('la reprise laisse la page restaurer son tracé', (tester) async {
    final picked = await open(
      tester,
      RouteFetchResult(RouteFetchStatus.ok, const [], session),
    );

    await tester.tap(find.text('Continuer l\'itinéraire en cours'));
    await tester.pumpAndSettle();

    // Aucun token sur la cible : c'est l'absence de `fresh` qui fait reprendre,
    // et c'est le seul chemin vers une destination ad hoc, qui n'existe nulle
    // part côté serveur.
    expect(picked.value!.resume, isTrue);
    expect(picked.value!.shareToken, isNull);
    expect(
      picked.value!.url(baseUrl: 'https://sports.logicraft.ch').toString(),
      'https://sports.logicraft.ch/navigate',
    );
  });

  testWidgets('un site injoignable n\'empêche pas de reprendre', (tester) async {
    // Le tracé en cours vient du navigateur, pas du réseau : il n'a aucune
    // raison de tomber avec lui — et c'est justement au bord de la route, sans
    // 4G, qu'on rouvre l'appli en pleine séance.
    await open(
      tester,
      RouteFetchResult(RouteFetchStatus.failed, const [], session),
    );

    expect(find.text('Continuer l\'itinéraire en cours'), findsOneWidget);
  });
}
