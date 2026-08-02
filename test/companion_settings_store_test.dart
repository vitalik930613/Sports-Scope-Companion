import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/dashboard/companion_settings_store.dart';
import 'package:sports_scope_companion/dashboard/ride_preset.dart';

/// Le cache des profils, et le choix du cycliste.
///
/// Il sert au même endroit que celui des itinéraires : un parking de départ,
/// sans réseau. Ce qu'on vérifie ici, c'est qu'il survive à la fermeture de
/// l'appli, qu'il ne mente pas, et surtout qu'il **ne se laisse pas effacer par
/// un site qui n'a rien à dire**.
void main() {
  late Directory root;
  late File file;

  /// Un document à deux profils : de la route, et du home-trainer sans carte.
  Map<String, dynamic> document() => {
        'v': 1,
        'presets': [
          {
            'key': 'route',
            'name': 'Route',
            'pages': [
              {'kind': 'map'},
            ],
            'bands': [
              {
                'metrics': ['speed', 'power'],
              },
            ],
          },
          {
            'key': 'ht',
            'name': 'Home-trainer',
            'pages': [
              {
                'kind': 'grid',
                'rows': 1,
                'cols': 2,
                'cells': [
                  {
                    'col': 0,
                    'block': {'kind': 'metric', 'metric': 'power'},
                  },
                  {
                    'col': 1,
                    'block': {'kind': 'metric', 'metric': 'cadence'},
                  },
                ],
              },
            ],
            'sensors': {'gps': false, 'radar': false},
          },
        ],
      };

  setUp(() async {
    root = await Directory.systemTemp.createTemp('companion_settings_test');
    file = File(p.join(root.path, 'companion_settings.json'));
  });

  tearDown(() => root.delete(recursive: true));

  test('le tableau de bord intégré tant que rien n\'est arrivé', () async {
    final store = CompanionSettingsStore(file);
    await store.load();

    expect(store.preset.key, RidePreset.builtIn.key);
    expect(store.hasChoice, isFalse);
    // `null` et pas une date : c'est ce qui distingue « pas de profil » de « on
    // n'a jamais demandé ».
    expect(store.updatedAt, isNull);
  });

  test('ce qui est enregistré se relit après redémarrage', () async {
    await CompanionSettingsStore(file).record(document());

    final reopened = CompanionSettingsStore(file);
    await reopened.load();

    expect(reopened.settings.presets, hasLength(2));
    expect(reopened.hasChoice, isTrue);
    expect(reopened.preset.key, 'route');
    expect(reopened.updatedAt, isNotNull);
  });

  test('le profil choisi survit au redémarrage', () async {
    final store = CompanionSettingsStore(file);
    await store.record(document());
    await store.select('ht');

    final reopened = CompanionSettingsStore(file);
    await reopened.load();

    expect(reopened.selectedKey, 'ht');
    expect(reopened.preset.name, 'Home-trainer');
    expect(reopened.preset.hasMap, isFalse);
    expect(reopened.preset.sensors.gps, isFalse);
  });

  test('une clé choisie que le site a supprimée ne bloque pas le départ', () async {
    final store = CompanionSettingsStore(file);
    await store.record(document());
    await store.select('ht');

    // Le site ne sert plus que la route.
    await store.record({
      'presets': [
        {
          'key': 'route',
          'name': 'Route',
          'pages': [
            {'kind': 'map'},
          ],
          'bands': [
            {
              'metrics': ['speed'],
            },
          ],
        },
      ],
    });

    expect(store.preset.key, 'route');
    // La clé reste retenue : le site peut rétablir le profil demain.
    expect(store.selectedKey, 'ht');
  });

  test('un document sans profil exploitable ne remplace pas le cache', () async {
    // C'est le cas du site plus ancien que l'appli (404 sur l'endpoint, ou
    // réponse tronquée). Écraser ferait perdre des profils parfaitement
    // valables reçus la veille — et les perdre au départ, sans réseau pour les
    // récupérer.
    final store = CompanionSettingsStore(file);
    await store.record(document());

    await store.record(<String, dynamic>{});
    await store.record(null);
    await store.record('<html>oups</html>');

    expect(store.settings.presets, hasLength(2));
  });

  test('un cache illisible repart du tableau de bord intégré', () async {
    await file.writeAsString('{ ceci n\'est pas du JSON');

    final store = CompanionSettingsStore(file);
    await store.load();

    expect(store.preset.key, RidePreset.builtIn.key);
  });

  test('le document est gardé brut, pas le modèle décodé', () async {
    // Une version plus récente de l'appli doit pouvoir comprendre un composant
    // qu'une version plus ancienne avait rapporté sans savoir le lire — sans
    // quoi une mise à jour obligerait à repasser par le réseau pour retrouver ce
    // qui était déjà sur le téléphone.
    final raw = document();
    (raw['presets'] as List).first['pages'] = [
      {'kind': 'map'},
      {'kind': 'hologramme_3d', 'title': 'Venu du futur'},
    ];

    await CompanionSettingsStore(file).record(raw);

    final onDisk = jsonDecode(await file.readAsString()) as Map;
    final pages =
        ((onDisk['document'] as Map)['presets'] as List).first['pages'] as List;

    expect(pages, hasLength(2));
    expect(pages.last['kind'], 'hologramme_3d');
  });
}
