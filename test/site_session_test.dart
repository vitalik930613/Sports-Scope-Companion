import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/account/site_session.dart';

void main() {
  late Directory root;
  late SiteSession session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('site_session_test');
    session = SiteSession(File(p.join(root.path, 'site_session.json')));
    await session.load();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('une session jamais observée est inconnue, pas déconnectée', () {
    expect(session.signedIn, isNull);
    expect(session.checkedAt, isNull);
  });

  test('l\'état observé se relit au démarrage suivant', () async {
    await session.record(true);

    final reopened = SiteSession(File(p.join(root.path, 'site_session.json')));
    await reopened.load();

    expect(reopened.signedIn, isTrue);
    expect(reopened.checkedAt, isNotNull);
  });

  test('une page muette laisse l\'état précédent intact', () async {
    await session.record(true);
    // Page de Keycloak ou écran d'erreur hors ligne : rien à en conclure, et
    // surtout pas une déconnexion.
    await session.record(null);

    expect(session.signedIn, isTrue);
  });

  test('une déconnexion constatée est retenue', () async {
    await session.record(true);
    await session.record(false);

    final reopened = SiteSession(File(p.join(root.path, 'site_session.json')));
    await reopened.load();

    expect(reopened.signedIn, isFalse);
  });

  test('seul un changement d\'état notifie les écrans', () async {
    var notifications = 0;
    session.addListener(() => notifications++);

    await session.record(true);
    await session.record(true);

    expect(notifications, 1);
  });

  test('un fichier illisible ne bloque pas le démarrage', () async {
    final file = File(p.join(root.path, 'corrompu.json'));
    await file.writeAsString('{ tronqué');

    final broken = SiteSession(file);
    await broken.load();

    expect(broken.signedIn, isNull);
  });
}
