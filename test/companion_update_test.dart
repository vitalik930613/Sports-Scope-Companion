import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/update/companion_release.dart';
import 'package:sports_scope_companion/update/update_checker.dart';

String body({
  Object? versionName = '0.2.0',
  Object? versionCode = 2,
  Object? downloadUrl = 'https://sports.logicraft.ch/companion',
  Object? size = 19000000,
}) =>
    jsonEncode({
      'version_name': versionName,
      'version_code': versionCode,
      'download_url': downloadUrl,
      'size': size,
    });

void main() {
  group('CompanionRelease.parse', () {
    test('lit ce que publie le site', () {
      final release = CompanionRelease.parse(body())!;

      expect(release.versionName, '0.2.0');
      expect(release.versionCode, 2);
      expect(release.downloadUrl, 'https://sports.logicraft.ch/companion');
      expect(release.size, 19000000);
    });

    // Le site peut être plus ancien que l'appli, répondre une page d'erreur HTML
    // ou un JSON amputé. Rien de tout ça ne doit remonter en exception : c'est
    // appelé au lancement, dans un `initState`.
    test('ne lève jamais sur une réponse illisible', () {
      expect(CompanionRelease.parse(''), isNull);
      expect(CompanionRelease.parse('<html>502</html>'), isNull);
      expect(CompanionRelease.parse('[]'), isNull);
      expect(CompanionRelease.parse('{"version_code": "deux"}'), isNull);
    });

    // Une carte « mise à jour disponible » dont le tap ne mène nulle part est
    // pire que pas de carte du tout.
    test('sans URL de téléchargement, il n\'y a rien à proposer', () {
      expect(CompanionRelease.parse(body(downloadUrl: null)), isNull);
      expect(CompanionRelease.parse(body(downloadUrl: '')), isNull);
    });

    test('sans versionCode exploitable, rien non plus', () {
      expect(CompanionRelease.parse(body(versionCode: 0)), isNull);
      expect(CompanionRelease.parse(body(versionCode: -1)), isNull);
      expect(CompanionRelease.parse(body(versionCode: null)), isNull);
    });

    // Le nom est cosmétique : son absence ne doit pas faire perdre une mise à
    // jour réelle, le numéro de build fait un repli lisible.
    test('sans nom de version, le build sert de nom', () {
      expect(CompanionRelease.parse(body(versionName: null))!.versionName, '2');
    });

    test('une taille absurde est ignorée plutôt que montrée', () {
      expect(CompanionRelease.parse(body(size: 0))!.size, isNull);
      expect(CompanionRelease.parse(body(size: 'gros'))!.size, isNull);
    });
  });

  group('isNewerThan', () {
    test('strictement supérieur : la version installée ne se propose pas', () {
      final release = CompanionRelease.parse(body(versionCode: 7))!;

      expect(release.isNewerThan(6), isTrue);
      expect(release.isNewerThan(7), isFalse);
    });

    // Un build de dev en avance sur la prod ne doit pas se voir offrir un retour
    // en arrière.
    test('une version plus ancienne que l\'installée ne se propose pas', () {
      expect(CompanionRelease.parse(body(versionCode: 3))!.isNewerThan(9), isFalse);
    });

    // Le piège que le versionCode évite : en texte, « 0.10.0 » passe pour plus
    // ancien que « 0.9.0 ».
    test('l\'ordre vient du build, jamais du nom', () {
      final ten = CompanionRelease.parse(
          body(versionName: '0.10.0', versionCode: 10))!;
      expect(ten.versionName.compareTo('0.9.0'), lessThan(0));
      expect(ten.isNewerThan(9), isTrue);
    });
  });

  group('UpdateChecker', () {
    UpdateChecker checkerFor(String? response, {int installed = 1}) =>
        UpdateChecker(
          fetch: (_) async => response,
          installedCode: () async => installed,
        );

    test('propose la version publiée quand elle est plus récente', () async {
      final checker = checkerFor(body(versionCode: 5), installed: 4);
      await checker.check();

      expect(checker.available?.versionCode, 5);
    });

    test('ne propose rien quand on est déjà à jour', () async {
      final checker = checkerFor(body(versionCode: 5), installed: 5);
      await checker.check();

      expect(checker.available, isNull);
    });

    // Hors ligne avant de partir est le cas banal : le contrôle doit se taire,
    // pas échouer.
    test('hors ligne, rien ne remonte et rien ne lève', () async {
      final checker = UpdateChecker(
        fetch: (_) async => throw const SocketExceptionStub(),
        installedCode: () async => 1,
      );

      await checker.check();
      expect(checker.available, isNull);
    });

    test('une réponse vide (rien de publié) ne propose rien', () async {
      final checker = checkerFor(null);
      await checker.check();

      expect(checker.available, isNull);
    });

    test('prévient ses auditeurs quand une version apparaît', () async {
      final checker = checkerFor(body(versionCode: 9), installed: 1);
      var notified = 0;
      checker.addListener(() => notified++);

      await checker.check();
      expect(notified, 1);

      // Deuxième contrôle identique : rien de neuf à annoncer, donc pas de
      // reconstruction de l'écran d'accueil.
      await checker.check();
      expect(notified, 1);
    });
  });
}

/// Faux échec réseau : `SocketException` demanderait `dart:io` pour rien ici.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
