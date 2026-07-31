import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/account/rider_profile.dart';
import 'package:sports_scope_companion/account/rider_profile_store.dart';

/// La charge utile telle que `/api/rider_profile` la renvoie, relayée par la page.
Map<String, dynamic> payload({Map<String, dynamic> over = const {}}) => {
      'ftp': {'watts': 250, 'source': 'manual', 'w_per_kg': 3.6},
      'lthr': 170,
      'lthr_source': 'auto',
      'weight_kg': 69.4,
      'power_zones': [
        {'key': 'z1', 'lo': 0, 'hi': 138},
        {'key': 'z2', 'lo': 138, 'hi': 188},
        {'key': 'z3', 'lo': 188, 'hi': 225},
        {'key': 'z4', 'lo': 225, 'hi': 263},
        {'key': 'z5', 'lo': 263, 'hi': 300},
        {'key': 'z6', 'lo': 300, 'hi': 375},
        {'key': 'z7', 'lo': 375, 'hi': null},
      ],
      'hr_zones': [
        {'key': 'z1', 'lo': 0, 'hi': 138},
        {'key': 'z5', 'lo': 170, 'hi': null},
      ],
      ...over,
    };

void main() {
  group('RiderProfile', () {
    test('décode une réponse complète', () {
      final profile = RiderProfile.fromJson(payload());

      expect(profile.ftpWatts, 250);
      expect(profile.ftpSource, 'manual');
      expect(profile.wPerKg, 3.6);
      expect(profile.lthr, 170);
      // Le seuil cardiaque peut désormais être estimé par le site, comme la FTP :
      // l'appli garde d'où il vient, elle ne le recalcule jamais.
      expect(profile.lthrSource, 'auto');
      expect(profile.weightKg, 69.4);
      expect(profile.powerZones, hasLength(7));
      expect(profile.hasPowerZones, isTrue);
    });

    test('trouve la zone d\'une puissance', () {
      final profile = RiderProfile.fromJson(payload());

      expect(profile.powerZoneFor(230)?.key, 'z4');
      expect(profile.powerZoneFor(0)?.key, 'z1');
      // Au-delà de la dernière borne, la zone ouverte prend le relais.
      expect(profile.powerZoneFor(1200)?.key, 'z7');
    });

    test('un compte sans FTP n\'a pas de zones', () {
      // Le site renvoie une liste vide plutôt que des zones sur un seuil deviné.
      final profile = RiderProfile.fromJson(payload(over: {
        'ftp': {'watts': null, 'source': null, 'w_per_kg': null},
        'power_zones': [],
      }));

      expect(profile.ftpWatts, isNull);
      expect(profile.hasPowerZones, isFalse);
      expect(profile.powerZoneFor(200), isNull);
    });

    test('ne jette pas sur une charge utile inattendue', () {
      expect(RiderProfile.fromJson(null).ftpWatts, isNull);
      expect(RiderProfile.fromJson('bonjour').hasPowerZones, isFalse);
      expect(RiderProfile.fromJson({'ftp': 'oui', 'power_zones': 'non'}).ftpWatts,
          isNull);
    });

    test('écarte les zones mal formées sans perdre les autres', () {
      final profile = RiderProfile.fromJson(payload(over: {
        'power_zones': [
          {'key': 'z1', 'lo': 0, 'hi': 138},
          {'lo': 138},
          'bogus',
          {'key': 'z3', 'lo': 188, 'hi': null},
        ],
      }));

      expect(profile.powerZones.map((z) => z.key), ['z1', 'z3']);
    });
  });

  group('RiderProfileStore', () {
    late Directory root;
    late RiderProfileStore store;

    File file() => File(p.join(root.path, 'rider_profile.json'));

    setUp(() async {
      root = await Directory.systemTemp.createTemp('rider_profile_test');
      store = RiderProfileStore(file());
      await store.load();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('un profil jamais reçu est vide', () {
      expect(store.profile.ftpWatts, isNull);
      expect(store.profile.hasPowerZones, isFalse);
      expect(store.updatedAt, isNull);
    });

    test('le profil se relit au démarrage suivant', () async {
      // C'est ce qui rend les zones disponibles sur une sortie démarrée hors
      // réseau, là où la page ne pourra rien pousser.
      await store.record(RiderProfile.fromJson(payload()));

      final reopened = RiderProfileStore(file());
      await reopened.load();

      expect(reopened.profile.ftpWatts, 250);
      expect(reopened.profile.lthr, 170);
      expect(reopened.profile.powerZones, hasLength(7));
      expect(reopened.profile.powerZoneFor(230)?.key, 'z4');
      expect(reopened.updatedAt, isNotNull);
    });

    test('un profil vide n\'écrase pas celui qu\'on avait', () async {
      // Ouvrir une navigation partagée en anonyme ne doit pas faire perdre des
      // zones parfaitement valables reçues la veille.
      await store.record(RiderProfile.fromJson(payload()));
      await store.record(RiderProfile.empty);

      expect(store.profile.ftpWatts, 250);
    });

    test('un fichier corrompu repart sur un profil vide, sans jeter', () async {
      await file().writeAsString('{ ceci n\'est pas du JSON');

      final reopened = RiderProfileStore(file());
      await reopened.load();

      expect(reopened.profile.ftpWatts, isNull);
      expect(reopened.updatedAt, isNull);
    });

    test('prévient ses auditeurs à chaque profil retenu', () async {
      var calls = 0;
      store.addListener(() => calls++);

      await store.record(RiderProfile.fromJson(payload()));
      expect(calls, 1);

      // Un profil vide est ignoré : pas de notification non plus.
      await store.record(RiderProfile.empty);
      expect(calls, 1);
    });
  });
}
