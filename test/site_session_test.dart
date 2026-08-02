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

  group('SignInWatcher', () {
    test('une connexion qui aboutit referme l\'écran', () {
      final watcher = SignInWatcher();

      // La page d'accueil anonyme, puis Keycloak, puis le retour connecté.
      expect(watcher.read(false), isFalse);
      expect(watcher.read(null), isFalse);
      expect(watcher.read(true), isTrue);
    });

    test('ouvrir Compte en étant déjà connecté ne referme rien', () {
      // Sinon l'écran claquerait à la seconde où on l'ouvre pour vérifier sa
      // session — ou pour se déconnecter, ce qui deviendrait impossible.
      final watcher = SignInWatcher();

      expect(watcher.read(true), isFalse);
      expect(watcher.read(true), isFalse);
    });

    test('une seule fermeture, même si la page se recharge', () {
      // `onPageFinished` tire plusieurs fois pour une même page : deux `pop`
      // dépileraient l'accueil avec.
      final watcher = SignInWatcher();
      watcher.read(false);

      expect(watcher.read(true), isTrue);
      expect(watcher.read(true), isFalse);
    });

    test('une page muette n\'efface pas la déconnexion déjà vue', () {
      // Keycloak et les écrans d'erreur rendent `null` : ils ne concluent rien.
      // Les compter comme « on ne sait plus » ferait rater le front juste après.
      final watcher = SignInWatcher();
      watcher.read(false);

      expect(watcher.read(null), isFalse);
      expect(watcher.read(null), isFalse);
      expect(watcher.read(true), isTrue);
    });

    test('le verrou tient : un écran ne se referme qu\'une fois', () {
      // Après le `pop`, le widget est démonté et son guetteur avec — celui-ci
      // n'a donc pas à savoir rejouer. Ce qui compte est qu'il ne redemande
      // JAMAIS une fermeture : un second `pop` dépilerait l'accueil.
      final watcher = SignInWatcher();
      watcher.read(false);
      expect(watcher.read(true), isTrue);

      expect(watcher.read(false), isFalse);
      expect(watcher.read(true), isFalse);
    });
  });
}
