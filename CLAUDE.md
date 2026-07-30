# Sports Scope Companion — Guide pour Claude

Appli Android compagnon de **sports-scope** (le site Rails, repo voisin
`~/dev/sports-scope`). Elle apporte à la navigation web ce qu'un navigateur ne
sait pas faire : les **capteurs BLE**, l'**enregistrement d'une sortie** en
`.fit`, le **rétroéclairage**, et un **tableau de bord** natif autour de la
carte.

`HOWTO.md` est le mode d'emploi (connexion au téléphone, connexion au site,
enregistrement, export `.fit`). Ce fichier-ci décrit le code.

## Stack

- **Flutter / Dart** (SDK ≥ 3.12), Material 3, Android uniquement
- **BLE** : `flutter_blue_plus` (épinglé — l'API bouge d'une mineure à l'autre)
- **WebView** : `webview_flutter` + `webview_flutter_android`
- **GPS** : `geolocator`, service au premier plan compris
- **Son** : `audioplayers`, pour les seules alertes radar
- Persistance : **des fichiers**, pas de base de données (JSON et JSONL)
- Aucun gestionnaire d'état : `ChangeNotifier` et `ValueNotifier`, rien d'autre

## Commandes

Le CLI Flutter tourne **sur l'hôte**, pas dans Docker — contrairement au repo
Rails voisin.

```bash
flutter analyze          # doit rester à « No issues found! »
flutter test             # ~200 tests, tous en dur (pas de golden, pas de mock)
flutter run              # sur le téléphone connecté en adb (voir HOWTO.md)
flutter run --dart-define=SPORTS_SCOPE_URL=http://192.168.1.20:3000
```

Pas de CI, pas de hook : `flutter analyze` + `flutter test` avant de conclure.

Cible par défaut : `https://sports.logicraft.ch`
(`sportsScopeBaseUrl`, `lib/navigation/navigation_target.dart`).

## Structure

```
lib/
  main.dart              # écran des capteurs (l'accueil) + amorçage des magasins
  drivetrain.dart        # dents et circonférence : traduit une position Di2
  account/               # session du site, seuils du cycliste, écran Compte
  ble/                   # scan, connexion, décodeurs GATT, hub d'échantillons
  devices/               # les appareils appairés, sur disque
  lighting/              # décision d'éclairage (modes) + envoi au feu
  navigation/            # cible de navigation, pont capteurs→page, luminosité
  recording/             # enregistreur, magasin de sorties, agrégats, .fit
  ride/                  # le tableau de bord de sortie (la coquille + ses pages)
  ui/                    # tuiles et formats partagés entre écrans
assets/sounds/           # tonalités d'alerte radar — GÉNÉRÉES, ne pas éditer
tool/fit_sample.dart     # génère un .fit de test (voir HOWTO.md)
tool/radar_tones.dart    # (re)génère assets/sounds/ : dart run tool/radar_tones.dart
```

## Le WebView de navigation

**Choix structurant** : les ~8 000 lignes de navigation web (carte MapLibre,
virages, cols, POI, reroutage, tuiles hors-ligne) **ne sont pas réécrites en
Dart**. L'appli affiche la page du site et lui apporte les capteurs. Une seule
implémentation de la navigation à faire évoluer, côté Rails.

`NavigationWebController` (`lib/ride/navigation_web_view.dart`) est **créé une
fois par sortie** et survit à tout changement de page. Le détruire coûterait le
pointeur de virage, la progression, l'état de reroutage et les tuiles MapLibre
en mémoire — soit un rechargement complet en pleine sortie.

### Le pont, dans les deux sens

| Sens | Mécanisme |
|---|---|
| appli → page | JavaScript injecté : `window.sportsScopeCompanion.push(…)`, `.setOccluded(…)` |
| page → appli | canal `SportsScopeCompanion`, un JSON par message |

Messages reçus, triés dans `_onPageMessage` (`ride_shell_page.dart`) :

| `type` | Sens |
|---|---|
| `ready` | le pont de la page est en place |
| `nav` | virage, progression, hors-trace, arrivée, col |
| `rider_profile` | les seuils du cycliste, relayés depuis le site |
| `screen` | la page entre ou sort de sa veille et demande la luminosité |

Un envoi vers une page qui n'a pas (encore) le pont est **perdu, jamais fatal** :
la navigation doit marcher sans capteurs, et le site peut être plus ancien que
l'appli.

Côté site, tout ça vit dans `app/javascript/companionBridge.ts` et
`RouteNavigation.vue` (`inCompanionApp()`, `appOwnsChrome`) du repo Rails.
**Toucher au protocole demande de modifier les deux dépôts.**

## Le tableau de bord de sortie (`lib/ride/`)

`RideShellPage` est la coquille : plein écran, rétroéclairage, zones obstruées
publiées vers la page, bouton retour, et les pages du tableau de bord.

- **Une pile** : le WebView est au fond, monté et peint **en permanence** ; les
  pages de données glissent par-dessus. Décidé après mesure sur route — une vue
  plateforme démontée, ou seulement sortie de la liste de peinture, cesse de
  suivre le cycliste. `setOccluded` prévient la page de couper ses animations
  sans rien endormir.
- **Catalogue circulaire** : `RidePage` (`ride_pages.dart`) liste les pages,
  navigation en tête. Le `PageView` est infini ; l'état est un index **brut**
  qui monte sans borne, replié par `pageOf()`, et `rawPageFor()` vise une page
  par le chemin court.
- **Répartition des gestes** — c'est le point délicat :

| Geste | Effet |
|---|---|
| glissé au milieu de la carte | déplace la carte (il appartient à MapLibre) |
| glissé/tap sur une bande de bord (`MapEdgeHandle`, 22 pt) | page précédente / suivante |
| glissé sur une page de données | fait défiler les pages |
| glissé sur le bandeau du bas | change de **jeu de valeurs**, jamais de page |
| pastilles du bandeau | vont directement à une page |

  La carte a besoin du glissé horizontal et un `PageView` réclame le même : tant
  que la carte est vivante, le `PageView` est mis **entièrement hors du test de
  touche** (`IgnorePointer`), la physique non défilante servant de second
  rideau. Le prédicat est `page == navigation && !scrolling` — **jamais l'index
  seul**, qui bascule à mi-glissé et couperait le geste en deux.

- `RideBottomBand` porte les jeux de valeurs (`RideBandSet`), qui bouclent eux
  aussi. Les zones viennent de `RiderProfileStore`, donc du site : **sans seuils
  connus, un tiret, jamais une zone calculée sur un seuil par défaut.**

### Retour automatique et radar

Toute la décision vit dans des classes pures, testées, qui ne touchent à aucun
widget — `AutoReturnPolicy` et `RideAlertSource` (`auto_return_policy.dart`),
`TurnProximity`, `radarViewFor` et `RadarAlertVoice`. La coquille ne fait que les
appeler et dessiner le résultat.

Trois règles y sont non négociables, chacune gardée par un test :

- **`arrived` est une impulsion, pas un état.** Le drapeau web ne retombe qu'au
  chargement d'un autre tracé ; pris pour un niveau, il collerait le cycliste sur
  la carte pour le reste de la sortie.
- **`absent` n'est pas `clear`.** Pas de radar ne veut pas dire route dégagée —
  ni à l'écran, ni au son. Le hub gardant la dernière valeur d'un capteur
  débranché, `radarViewFor` périme les trames au bout de 6 s.
- **Le cycliste garde le dernier mot.** Un changement de page à la main pendant
  une alerte suspend le retour auto jusqu'à extinction.

Le chien de garde lit `recorder.lastFix` plutôt que d'ouvrir un flux GPS à lui :
conséquence assumée, **hors enregistrement il n'a pas de position** et le retour
auto repose entièrement sur le pont.

## Ajouter un capteur BLE

Une seule entrée à écrire : un `SensorProfile` dans `sensorProfiles`
(`lib/ble/sensor_profile.dart`), qui relie une capacité (`SensorKind`) au
service et à la caractéristique GATT, plus le décodeur. Ni `SensorConnection`,
ni `SensorHub`, ni l'UI n'ont à être touchés.

Le décodeur implémente `CharacteristicDecoder` (`lib/ble/characteristic_decoder.dart`) :

- il **ne lève jamais** — une trame incomprise rend une liste vide ;
- `readOnConnect` pour les capteurs qui ne notifient que sur *changement* (le
  Di2, dont la position n'arriverait sinon qu'au premier changement de vitesse) ;
- `reset()` remet à zéro l'état cumulé après une reconnexion, sinon un delta
  calculé à cheval sort une cadence absurde.

## Enregistrement et persistance

Tout est en fichiers dans le dossier applicatif, réécrits en entier via un
temporaire renommé (`known_devices.json`, `site_session.json`,
`rider_profile.json`) — une coupure ne laisse jamais un fichier à moitié écrit.

Les sorties, elles, sont en **ajout** :

```
rides/2026-07-28T14-03-11Z/session.json   ← résumé, réécrit toutes les 30 s
rides/2026-07-28T14-03-11Z/points.jsonl   ← un point par seconde, en ajout
```

Au pire d'une coupure, la dernière ligne est tronquée et tout le reste reste
lisible. Le `.fit` est **reconstruit depuis le JSONL à chaque export** : le
JSONL garde ce que le `.fit` ne sait pas porter (positions Di2, précision GPS).

Le cadencement est régulier, pas déclenché par le GPS : à l'arrêt ou sous un
tunnel, la trace continue de porter le cardio et la puissance. Un point sans
position est une information, pas un trou.

## Conventions de code

- **Les commentaires sont en français et disent le _pourquoi_**, pas le quoi :
  la mesure qui a tranché un choix, le piège qu'on évite, ce qui casserait si on
  faisait autrement. C'est la convention la plus visible du dépôt — s'y tenir.
  Un commentaire qui paraphrase la ligne suivante n'a pas sa place.
- Lints : `flutter_lints` + `prefer_final_locals` + `avoid_print`
  (`debugPrint`, avec un préfixe entre crochets : `[hub]`, `[profil]`).
- Une mesure absente s'affiche **`—`, jamais `0`** : un zéro se lit comme une
  mesure. Même règle dans `MetricTile` et dans le bandeau.
- Les tests sont de vrais tests unitaires sur la logique (décodeurs, agrégats,
  écriture `.fit`, gestes, machines à états), sans mock de plateforme. Dans un
  `testWidgets`, le temps est simulé : **une vraie entrée-sortie disque doit
  passer par `tester.runAsync()`**, sinon le test attend dix minutes puis meurt.

## Pièges connus

- `arrived` est **collant** côté web (remis à faux seulement au chargement d'un
  tracé) : tout ce qui s'en sert doit en détecter le **front**, pas le niveau,
  sous peine d'épingler le cycliste sur la carte pour le reste de la sortie.
- Le paquet s'appelle encore `com.example.sports_scope_companion` : tant que
  c'est le cas, l'App Link vérifié `https://` ne peut pas être activé et le
  passage de session repose sur le schéma `sportsscope://` + un jeton à usage
  unique (voir les notes de sécurité de `HOWTO.md`).
- Contre le serveur de dev, la connexion Keycloak ne peut pas aboutir depuis le
  téléphone (`keycloak.localtest.me` résout sur le téléphone lui-même). Tester
  la connexion contre la prod.
- `known_devices_store.dart` mentionne Drift dans un commentaire : **il n'y a
  pas de Drift dans le projet**, c'est un reste.
