import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/sensor_profile.dart';
import 'package:sports_scope_companion/dashboard/companion_settings.dart';
import 'package:sports_scope_companion/dashboard/dashboard_block.dart';
import 'package:sports_scope_companion/dashboard/metric_id.dart';
import 'package:sports_scope_companion/dashboard/ride_preset.dart';

/// Le décodage du document de réglages, et surtout **ce qu'il garantit**.
///
/// Ce document décide de ce qui s'affiche pendant la sortie : il vient du
/// réseau, il peut être plus récent que l'appli, tronqué, ou remplacé par du
/// HTML d'erreur. Chaque garantie a donc son test — le pire résultat imaginable
/// n'est pas « mes réglages ne sont pas arrivés », c'est un écran noir au départ
/// d'un col.
void main() {
  /// Un profil minimal valable, à décorer selon le test.
  Map<String, dynamic> preset(Map<String, dynamic> extra) => {
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
        ...extra,
      };

  CompanionSettings parse(Object? raw) => CompanionSettings.parse(raw);

  group('le repli', () {
    test('un document illisible rend le tableau de bord intégré', () {
      for (final raw in <Object?>[null, 'du HTML', 42, <String, dynamic>{}]) {
        final settings = parse(raw);
        expect(settings.presets, hasLength(1));
        expect(settings.presets.single.key, RidePreset.builtIn.key);
      }
    });

    test('un profil sans clé est retiré, pas fatal', () {
      final settings = parse({
        'presets': [
          {'name': 'Sans clé'},
          preset({}),
        ],
      });

      expect(settings.presets, hasLength(1));
      expect(settings.presets.single.key, 'route');
    });

    test('le profil intégré est exactement le tableau de bord d\'avant', () {
      // Carte puis Effort, et les deux jeux de valeurs du bandeau : c'est ce
      // qu'il faut retrouver quand tout le reste tombe, sans rien de nouveau à
      // apprendre le jour où ça arrive.
      const builtIn = RidePreset.builtIn;

      expect(builtIn.pages, hasLength(2));
      expect(builtIn.pages.first, isA<MapPageSpec>());
      expect(builtIn.mapPageIndex, 0);
      expect(builtIn.bands, hasLength(2));
      expect(builtIn.bands.first.metrics.first, MetricId.duration);
    });
  });

  group('les pages', () {
    test('la carte se place où l\'on veut', () {
      final settings = parse({
        'presets': [
          preset({
            'pages': [
              {
                'kind': 'list',
                'title': 'Effort',
                'blocks': [
                  {'kind': 'recording'},
                ],
              },
              {'kind': 'map'},
            ],
          }),
        ],
      });

      expect(settings.presets.single.mapPageIndex, 1);
    });

    test('un profil sans carte n\'en fabrique pas une', () {
      // C'est le home-trainer : pas de carte, donc pas de WebView, pas de GPS
      // de page, pas de retour automatique.
      final settings = parse({
        'presets': [
          preset({
            'pages': [
              {
                'kind': 'grid',
                'rows': 1,
                'cols': 1,
                'cells': [
                  {
                    'block': {'kind': 'metric', 'metric': 'power'},
                  },
                ],
              },
            ],
          }),
        ],
      });

      expect(settings.presets.single.hasMap, isFalse);
      expect(settings.presets.single.mapPageIndex, isNull);
    });

    test('la deuxième carte est retirée', () {
      // Deux cartes voudraient dire deux identités pour un seul WebView, alors
      // que l'instance MapLibre est unique et doit le rester.
      final settings = parse({
        'presets': [
          preset({
            'pages': [
              {'kind': 'map'},
              {'kind': 'map'},
            ],
          }),
        ],
      });

      expect(settings.presets.single.pages, hasLength(1));
    });

    test('un profil vidé de ses pages retombe sur la page Effort', () {
      // On ne monte jamais une coquille sans contenu : un écran noir en pleine
      // sortie ne se diagnostique pas au guidon.
      final settings = parse({
        'presets': [
          preset({
            'pages': [
              {'kind': 'inconnu'},
              {'kind': 'list', 'blocks': <Object>[]},
            ],
          }),
        ],
      });

      final pages = settings.presets.single.pages;
      expect(pages, hasLength(1));
      expect(pages.single, isA<ListPageSpec>());
    });

    test('une grille sans cellule plaçable est retirée comme page', () {
      final settings = parse({
        'presets': [
          preset({
            'pages': [
              {'kind': 'map'},
              {
                'kind': 'grid',
                'rows': 2,
                'cols': 2,
                'cells': [
                  {
                    'row': 9,
                    'col': 9,
                    'block': {'kind': 'metric', 'metric': 'power'},
                  },
                ],
              },
            ],
          }),
        ],
      });

      expect(settings.presets.single.pages, hasLength(1));
    });

    test('une grille garde ses fusions et écarte les recouvrements', () {
      final settings = parse({
        'presets': [
          preset({
            'pages': [
              {
                'kind': 'grid',
                'title': 'Chiffres',
                'rows': 3,
                'cols': 3,
                'cells': [
                  {
                    'row': 1,
                    'col': 0,
                    'col_span': 3,
                    'block': {'kind': 'zones', 'source': 'power', 'mode': 'bar_only'},
                  },
                  // Celle-ci tombe dans la ligne fusionnée : elle passe à la
                  // trappe, la première posée gagnant.
                  {
                    'row': 1,
                    'col': 2,
                    'block': {'kind': 'metric', 'metric': 'power'},
                  },
                  {
                    'row': 2,
                    'col': 0,
                    'block': {'kind': 'metric', 'metric': 'speed', 'mode': 'big'},
                  },
                ],
              },
            ],
          }),
        ],
      });

      final page = settings.presets.single.pages.single as GridPageSpec;
      expect(page.cells, hasLength(2));
      expect(page.cells.first.span.colSpan, 3);
      expect(page.cells.first.block, const ZonesBlock(
        source: ZonesSource.power,
        mode: ZonesMode.barOnly,
      ));
    });
  });

  group('les composants', () {
    test('un mode inconnu retombe sur le mode par défaut', () {
      // Le site peut être plus récent que l'appli. Une page qui refuserait de se
      // dessiner en pleine sortie serait le pire résultat possible.
      final block = DashboardBlock.parse({
        'kind': 'metric',
        'metric': 'power',
        'mode': 'hologramme',
      });

      expect(block, const MetricBlock(metric: MetricId.power));
      expect((block! as MetricBlock).mode, MetricMode.big);
    });

    test('la jauge radar se pose dans les deux sens', () {
      // Deux clés et non un booléen : c'est le mode qui décide du dessin, ici
      // comme partout, et le site en déplie une vignette par sens.
      expect(
        DashboardBlock.parse({'kind': 'radar', 'mode': 'gauge_vertical'}),
        const RadarBlock(mode: RadarMode.gaugeVertical),
      );
      expect(
        DashboardBlock.parse({'kind': 'radar', 'mode': 'gauge'}),
        const RadarBlock(mode: RadarMode.gauge),
      );
      // Le premier de la liste, comme pour tout mode inconnu.
      expect(
        DashboardBlock.parse({'kind': 'radar', 'mode': 'renversée'}),
        const RadarBlock(mode: RadarMode.distance),
      );
    });

    test('une mesure inconnue retire la cellule plutôt que d\'afficher un tiret',
        () {
      expect(
        DashboardBlock.parse({'kind': 'metric', 'metric': 'temperature_rectale'}),
        isNull,
      );
    });

    test('la cellule vide se distingue de la cellule incomprise', () {
      // La première est un choix de composition, la seconde un symptôme.
      expect(DashboardBlock.parse({'kind': 'empty'}), const EmptyBlock());
      expect(DashboardBlock.parse({'kind': 'boussole'}), isNull);
    });
  });

  group('le bandeau', () {
    test('cinq mesures sont tronquées à quatre', () {
      // Au-delà de quatre cases, les chiffres ne se lisent plus d'un coup d'œil
      // en roulant, ce qui est le seul usage du bandeau.
      final settings = parse({
        'presets': [
          preset({
            'bands': [
              {
                'metrics': [
                  'duration',
                  'distance',
                  'speed',
                  'power',
                  'heart_rate',
                ],
              },
            ],
          }),
        ],
      });

      expect(settings.presets.single.bands.single.metrics, hasLength(4));
    });

    test('un jeu sans mesure connue est retiré', () {
      final settings = parse({
        'presets': [
          preset({
            'bands': [
              {
                'metrics': ['pouls_lunaire'],
              },
              {
                'metrics': ['power'],
              },
            ],
          }),
        ],
      });

      expect(settings.presets.single.bands, hasLength(1));
    });

    test('sans aucun jeu valable, ceux d\'origine reviennent', () {
      final settings = parse({
        'presets': [
          preset({'bands': <Object>[]}),
        ],
      });

      expect(settings.presets.single.bands, hasLength(2));
    });
  });

  group('les capteurs', () {
    test('un capteur non mentionné est activé', () {
      // Le vide ne coupe rien : un document plus ancien que l'appli, ou écrit à
      // la main, ne doit jamais éteindre un capteur en silence — l'erreur irait
      // dans le mauvais sens, une sortie sans cardio ne se rattrapant pas.
      final settings = parse({
        'presets': [
          preset({
            'sensors': {'gps': false},
          }),
        ],
      });

      final sensors = settings.presets.single.sensors;
      expect(sensors.gps, isFalse);
      expect(sensors.heartRate, isTrue);
      expect(sensors.barometer, isTrue);
      expect(sensors.allows(SensorKind.radar), isTrue);
    });

    test('sans bloc « sensors », tout est activé', () {
      final settings = parse({
        'presets': [preset({})],
      });

      final sensors = settings.presets.single.sensors;
      for (final kind in SensorKind.values) {
        expect(sensors.allows(kind), isTrue, reason: kind.name);
      }
      expect(sensors.gps, isTrue);
    });

    test('un profil de home-trainer coupe ce qu\'il faut', () {
      final settings = parse({
        'presets': [
          preset({
            'sensors': {
              'gps': false,
              'barometer': false,
              'radar': false,
              'light': false,
            },
          }),
        ],
      });

      final sensors = settings.presets.single.sensors;
      expect(sensors.allows(SensorKind.radar), isFalse);
      expect(sensors.allows(SensorKind.power), isTrue);
    });
  });

  group('le choix du profil', () {
    test('deux profils de même clé : le premier gagne', () {
      // Sinon le choix au départ serait ambigu, et le choix retenu sur disque
      // indéterminé.
      final settings = parse({
        'presets': [
          preset({'name': 'Route'}),
          preset({'name': 'Route bis'}),
        ],
      });

      expect(settings.presets, hasLength(1));
      expect(settings.presets.single.name, 'Route');
    });

    test('une clé retenue mais disparue retombe sur le premier profil', () {
      // Le site a pu supprimer le profil depuis : le découvrir au moment de
      // partir ne doit pas empêcher de partir.
      final settings = parse({
        'presets': [preset({})],
      });

      expect(settings.select('vtt').key, 'route');
      expect(settings.select(null).key, 'route');
    });
  });

  group('les réglages', () {
    test('le radar se règle et se tait', () {
      final settings = parse({
        'presets': [
          preset({
            'radar': {'close_m': 25, 'sounds': false, 'wake_hold_s': 9},
          }),
        ],
      });

      final radar = settings.presets.single.radar;
      expect(radar.closeM, 25);
      expect(radar.sounds, isFalse);
      expect(radar.wakeHold, const Duration(seconds: 9));
      // Non mentionné : la valeur de la carte de diagnostic, pour que les deux
      // affichages racontent la même chose du même capteur.
      expect(radar.rangeM, 140);
      // L'habillage non plus n'est pas mentionné : il reste posé.
      expect(radar.overlay, isTrue);
    });

    test('l\'habillage radar se coupe sans couper le capteur', () {
      // Le profil qui ne veut du radar que dans ses composants : les tonalités
      // et le réveil d'écran, eux, ne dépendent pas de l'habillage.
      final settings = parse({
        'presets': [
          preset({
            'radar': {'overlay': false},
          }),
        ],
      });

      final radar = settings.presets.single.radar;
      expect(radar.overlay, isFalse);
      expect(radar.sounds, isTrue);
      expect(radar.wakeScreen, isTrue);
      expect(settings.presets.single.sensors.radar, isTrue);
    });

    test('la veille ne descend jamais sous 1 %', () {
      // À zéro, certains appareils coupent franchement le rétroéclairage, et le
      // bandeau deviendrait illisible même de nuit.
      final settings = parse({
        'presets': [
          preset({
            'screen': {'dim_level': 0},
          }),
        ],
      });

      expect(settings.presets.single.screen.dimLevel, 0.01);
    });

    test('les seuils d\'éclairage traversent jusqu\'à LightingConfig', () {
      final settings = parse({
        'presets': [
          preset({
            'lighting': {'night_lux': 12, 'flash_at_night': true},
          }),
        ],
      });

      final config = settings.presets.single.lighting.config;
      expect(config.nightLux, 12);
      expect(config.flashAtNight, isTrue);
      expect(config.dayLux, 5000);
    });
  });
}
