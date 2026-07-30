import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/navigation/route_catalog_store.dart';
import 'package:sports_scope_companion/navigation/route_summary.dart';

/// Le cache est ce qui rend la liste utilisable là où on s'en sert : un parking
/// de départ, sans réseau. Ce qu'on vérifie ici, c'est qu'il survive à la
/// fermeture de l'appli — et qu'il ne mente pas.
void main() {
  late Directory root;
  late File file;

  const route = RouteSummary(
    id: 42,
    name: 'Col de la Croix',
    shareToken: 'abc123',
    distanceM: 34200,
    elevationGainM: 1210,
    activity: 'cycling',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('route_catalog_test');
    file = File(p.join(root.path, 'route_catalog.json'));
  });

  tearDown(() => root.delete(recursive: true));

  test('rien tant que rien n\'a été rapporté du site', () async {
    final store = RouteCatalogStore(file);
    await store.load();

    expect(store.routes, isEmpty);
    // `null` et pas une date : c'est ce qui distingue « aucun itinéraire » de
    // « on n'a jamais demandé ».
    expect(store.updatedAt, isNull);
  });

  test('ce qui est enregistré se relit après redémarrage', () async {
    await RouteCatalogStore(file).record([route]);

    final reopened = RouteCatalogStore(file);
    await reopened.load();

    expect(reopened.routes.single.name, 'Col de la Croix');
    expect(reopened.routes.single.shareToken, 'abc123');
    expect(reopened.routes.single.distanceM, 34200);
    expect(reopened.updatedAt, isNotNull);
  });

  test('une liste vide s\'enregistre : un itinéraire supprimé disparaît', () async {
    final store = RouteCatalogStore(file);
    await store.record([route]);
    await store.record(const []);

    final reopened = RouteCatalogStore(file);
    await reopened.load();

    expect(reopened.routes, isEmpty);
    // Mais on sait qu'on a demandé — sinon l'écran dirait « chargement » pour
    // un compte qui n'a simplement aucun itinéraire.
    expect(reopened.updatedAt, isNotNull);
  });

  test('un cache illisible repart de rien, sans lever', () async {
    await file.writeAsString('{ ceci n\'est pas du JSON');

    final store = RouteCatalogStore(file);
    await store.load();

    expect(store.routes, isEmpty);
  });

  test('la liste rendue ne se modifie pas depuis l\'extérieur', () async {
    final store = RouteCatalogStore(file);
    await store.record([route]);

    expect(() => store.routes.add(route), throwsUnsupportedError);
  });
}
