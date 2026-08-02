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
  main.dart              # l'accueil (naviguer, état des capteurs) + amorçage
  drivetrain.dart        # dents et circonférence : traduit une position Di2
  account/               # session du site, seuils du cycliste, écran Compte
  ble/                   # scan, connexion, décodeurs GATT, hub d'échantillons
  devices/               # les appareils appairés (disque) + la page d'appairage
  lighting/              # décision d'éclairage (modes) + envoi au feu
  navigation/            # cible de navigation, pont capteurs→page, luminosité
  phone/                 # capteurs du téléphone : baromètre, lumière, boussole
  recording/             # enregistreur, magasin de sorties, agrégats, .fit
  ride/                  # le tableau de bord de sortie (la coquille + ses pages)
  ui/                    # tuiles et formats partagés entre écrans
  update/                # « une version plus récente existe » (diffusion hors Play Store)
assets/sounds/           # tonalités d'alerte radar — GÉNÉRÉES, ne pas éditer
tool/fit_sample.dart     # génère un .fit de test (voir HOWTO.md)
tool/radar_tones.dart    # (re)génère assets/sounds/ : dart run tool/radar_tones.dart
```

## L'accueil et la page des capteurs

`HomePage` (`main.dart`) est l'écran de départ : **« Naviguer »**, l'état des
capteurs, et les cartes qui disent ce qui manquera sur la route (session,
seuils, enregistrement, valeurs en direct). L'appairage, lui, est une sous-page
(`devices/sensors_page.dart`) — on appaire un capteur une fois, on part rouler
tous les jours ; le scan et les listes n'ont pas à occuper l'écran qu'on ouvre
avant chaque sortie.

En tête de tout, mais **seulement quand on revient d'une sortie** : la carte
*Reprendre la navigation*, qui rouvre la sortie quittée là où on en était. La
cible vit dans un `ValueNotifier` de `SportsScopeApp` et non dans cet écran —
un lien entrant ouvre la navigation sans passer par l'accueil — et **rien n'en
est écrit sur disque** : au lancement suivant, la page peut avoir fini sa
navigation, et une reprise gardée d'un jour sur l'autre proposerait un tracé
qui n'existe plus (même raison que le catalogue, plus bas).

Ce qui en reste sur l'accueil est `SensorStatusStrip` : **une icône par capteur
connu, verte s'il est connecté, orange sinon**. La forme dit quel capteur, la
couleur dit s'il mesurera quelque chose. Deux couleurs et pas trois
(`sensorLinkColor`, `devices/sensor_link_status.dart`) : « hors ligne », « en
cours » et « échec » se ressemblent trop pour qu'on les distingue d'un coup
d'œil, et le détail est en toutes lettres sur la sous-page.

Troisième cas à part, qui n'est pas un état mais une **décision** : connexion
auto coupée → **gris et barré** (`SensorLinkStrike`). L'orange serait un
reproche et enverrait chercher une panne — c'est exactement ce qui est arrivé
avec un Di2 dont la connexion auto avait été coupée par mégarde. La barre
redouble la couleur parce qu'au soleil, gris et orange se confondent. Un capteur
écarté **mais connecté** reste vert : il mesure maintenant, c'est la reconnexion
future qu'on a désactivée. La rangée se
reconstruit sur `KnownDevicesStore` — c'est `remember()`, appelé au passage à
*connecté*, qui la fait verdir — et chaque pastille s'abonne en plus à
`connection.status`, pour le capteur qui décroche en route.

`DeviceLinker` (`devices/device_linker.dart`) porte le geste commun aux deux
écrans : connecter, puis **mémoriser à la connexion, jamais au tap** — tant que
l'appareil n'a pas répondu, on ne connaît ni son nom ni ses capacités. Une seule
instance, créée dans `main.dart` à côté du hub : son balayage (ci-dessous) doit
continuer pendant la sortie, écran empilé par-dessus. La reconnexion est
déclenchée par l'état de l'adaptateur et non par `initState` : au lancement
`adapterStateNow` vaut encore `unknown`.

### Rattacher un capteur : deux mécanismes, pas un

`connect(autoConnect: true)` délègue le rattachement à la pile Bluetooth du
téléphone. **Mesuré sur route, ça ne suffit pas pour tout le monde** : l'écoute
de fond d'Android est faite de fenêtres courtes et espacées. Elle attrape sans
peine le Di2 (appairé au téléphone) et ce qui émet en continu — radar allumé,
ceinture portée — et rate régulièrement le capteur qui n'émet que par à-coups :
un capteur de puissance se rendort dès que les manivelles s'arrêtent, et on
restait sur « connexion… » indéfiniment.

D'où un **balayage** dans `DeviceLinker` : tant qu'il manque un capteur connu,
scans courts (8 s toutes les ~53 s) ; un capteur vu émettre est rattaché
**en direct** (`SensorConnection.attachNow()`). Trois choses à ne pas défaire :

- `attachNow` **déconnecte avant de reconnecter** : tant que l'attente posée par
  `autoConnect` tient, flutter_blue_plus répond « already connecting » et laisse
  tomber la demande. La déconnexion n'est pas une précaution, c'est ce qui rend
  l'appel possible.
- Après un rattachement direct, flutter_blue_plus **referme** le canal GATT à la
  déconnexion suivante (il ne le garde ouvert que pour les `autoConnect`) :
  `_attachedDirectly` sert à reposer l'attente, sinon plus personne n'attend le
  capteur.
- `devicesToReattach` (pur, testé) filtre sur `autoConnect` : un capteur écarté à
  la main — vélo prêté, boîtier de l'autre vélo — n'est **jamais** rattrapé au
  vol parce qu'un scan l'a vu passer, sinon le réglage ne voudrait plus rien
  dire.

Le minuteur tourne même quand tout est connecté (il ne scanne alors rien) : c'est
ce qui rattrape le capteur qui décroche en pleine sortie. Et le guetteur écoute
les résultats de **n'importe quel** scan, y compris celui lancé à la main depuis
la page des capteurs.

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

### Appeler une API du site sans identifiants

L'appli ne détient aucun jeton : la session est un cookie du pot partagé par
tous les WebViews. Pour lire une API authentifiée, on **fait appeler un
WebView** plutôt que d'extraire le cookie — voir `RouteCatalogFetch`
(`navigation/route_catalog_fetch.dart`), qui charge une page du site hors écran
et y exécute `fetch('/api/routes', {credentials: 'same-origin'})`, résultat
renvoyé par un canal JS. `Accept: application/json` est indispensable : c'est ce
qui fait répondre à Rails un 401 propre au lieu d'une redirection HTML, donc ce
qui permet de distinguer « pas connecté » de « pas de réseau ». Le résultat va
dans un cache disque (`RouteCatalogStore`), qui fait autorité pour l'affichage —
on choisit son tracé au départ, là où le réseau manque.

Le **tracé en cours** voyage avec, par le même WebView : il vit dans le
`localStorage` du site (clé `sportsScope.navSession`, cf. `navSession.ts`), que
ce document partage puisqu'il en a l'origine. On n'en extrait que le nom, le
token et la date (`NavSessionSummary`) — la géométrie pèse des mégaoctets pour
afficher une ligne de liste, et c'est la page qui la restaurera. **Rien n'en est
mis en cache sur disque**, contrairement au catalogue : une entrée gardée après
que la page a fini sa navigation ferait proposer de reprendre un tracé qui
n'existe plus, et le tap retomberait sans un mot sur la carte nue.

### Les deux `/navigate`

Le même chemin fait deux choses, et **c'est `fresh=1` qui les sépare** :

| URL | Ce que fait la page |
|---|---|
| `/navigate?fresh=1` | efface son `localStorage` : carte nue (`NavigationTarget.free()`) |
| `/navigate` | restaure le tracé mémorisé (`NavigationTarget.resume()`) |
| `/routes/<token>/navigate` | charge cet itinéraire-là |

Oublier `fresh` fait rouvrir l'itinéraire de tout à l'heure au lieu de la
navigation libre — c'était le bug. Le paramètre doit aussi survivre au passage
par `/auth/handoff`, qui recopie `next` tel quel. Un **lien entrant** sans token,
lui, part toujours à neuf : on ne sait pas ce que la page a en mémoire, et la
reprise ne s'offre que dans le sélecteur, là où on a vraiment lu le stockage.

## Le tableau de bord de sortie (`lib/ride/`)

`RideShellPage` est la coquille : plein écran, rétroéclairage, zones obstruées
publiées vers la page, bouton retour, et les pages du tableau de bord.

- **Une pile** : le WebView est au fond, monté et peint **en permanence** ; les
  pages de données glissent par-dessus. Décidé après mesure sur route — une vue
  plateforme démontée, ou seulement sortie de la liste de peinture, cesse de
  suivre le cycliste. `setOccluded` prévient la page de couper ses animations
  sans rien endormir.
- **Changer de tracé en pleine sortie** passe par
  `NavigationWebController.openTarget()`, jamais par un contrôleur neuf : le
  tracé est choisi par l'URL, donc la page recharge — mais l'instance MapLibre,
  le pot de cookies, le pont des capteurs et le service worker, eux, survivent.
  Les commandes sont dans le menu de la page Effort (choisir un autre
  itinéraire, retirer celui en cours), pas sur la carte, qui n'a pas de pixels à
  donner. Retirer demande confirmation : `fresh=1` efface la session de la page,
  donc la progression avec elle. L'enregistrement, lui, n'est pas concerné — il
  vit au-dessus de la navigation.
- **Rentrer, et repartir** — un tap dans chaque sens, c'est la règle. Le bouton
  retour du téléphone descend d'au plus trois crans : page de données → carte,
  puis la page web **si elle s'est égarée ailleurs que sur le tracé ouvert**
  (`pageLeftTarget` compare les *chemins*, jamais les paramètres : `fresh=1`
  disparaît de l'URL une fois la session effacée), puis la sortie. Le cran du
  milieu dépilait auparavant tout l'historique du WebView : nombre d'appuis
  imprévisible, et chaque appui rouvrait au passage un tracé de la sortie — un
  retour arrière qui change d'itinéraire. Quitter ne demande **aucune
  confirmation** : on rentre souvent (voir l'enregistrement, un capteur) et une
  boîte à traverser à chaque fois rendrait l'aller-retour plus cher que ce qu'on
  va y chercher. Ce qui rend ça tenable, c'est la reprise : la coquille
  **rend en partant** (`Navigator.pop`) une `NavigationTarget.resume()` que
  l'accueil repropose en tête et en un tap — jamais le tracé par son token, qui
  repartirait de son début, là où la page sait où l'on en était. Et parce qu'un
  geste ne répond jamais à la question « comment on rentre ? », **« Revenir à
  l'accueil » est écrit en toutes lettres** au bas du menu de la page Effort,
  sous un séparateur : les autres commandes restent dans la sortie, celle-là en
  sort. L'enregistrement continue — c'est l'accueil qui le termine.
- **Catalogue circulaire** : `RidePage` (`ride_pages.dart`) liste les pages,
  navigation en tête. Le `PageView` est infini ; l'état est un index **brut**
  qui monte sans borne, replié par `pageOf()`, et `rawPageFor()` vise une page
  par le chemin court.
- **La page Effort dit le cumul, le bandeau dit l'instant** : temps passé par
  zone depuis le départ (barre + légende, **une carte pour le cardio et une pour
  la puissance**), moyennes cardio/puissance, cadence, D+, calories. Tout vient de
  l'enregistreur — **hors enregistrement, elle n'affiche rien** plutôt que des
  zéros. Le temps par zone se calcule d'un **histogramme** de mesures
  (`RideStats.hrHistogram` et `powerHistogram`, paliers de 5 bpm et 25 W comme le
  site) replié en zones à l'affichage (`zoneSharesOf`, `ride/zone_time.dart`) :
  un profil qui arrive en pleine sortie recolore alors le temps **déjà écoulé**,
  là où un compteur par zone ne vaudrait que pour la suite. Les deux cartes sont
  le même code à deux jeux d'arguments près, l'icône de la ligne courante
  comprise (cœur / éclair) : elles se ressemblent trop pour qu'on les distingue
  autrement. Empilées et non commutées par un sélecteur — le cardio traîne
  derrière l'effort et lisse les relances, la puissance les compte toutes, et
  c'est cet écart qu'on vient lire.
- **Répartition des gestes** — c'est le point délicat :

| Geste | Effet |
|---|---|
| glissé au milieu de la carte | déplace la carte (il appartient à MapLibre) |
| glissé/tap sur une bande de bord (`MapEdgeHandle`, 22 pt) | page précédente / suivante |
| glissé sur une page de données | fait défiler les pages |
| glissé sur le bandeau du bas | change de **jeu de valeurs**, jamais de page |
| pastilles du bandeau | vont directement à une page |
| tap sur les watts ou leur zone | ouvre la calibration du capteur de puissance |

  La carte a besoin du glissé horizontal et un `PageView` réclame le même : tant
  que la carte est vivante, le `PageView` est mis **entièrement hors du test de
  touche** (`IgnorePointer`), la physique non défilante servant de second
  rideau. Le prédicat est `page == navigation && !scrolling` — **jamais l'index
  seul**, qui bascule à mi-glissé et couperait le geste en deux.

- `RideBottomBand` porte les jeux de valeurs (`RideBandSet`), qui bouclent eux
  aussi. Les zones viennent de `RiderProfileStore`, donc du site : **jamais une
  zone calculée sur un seuil par défaut.** Sans seuil, la case zone affiche
  `LTHR ?` ou `FTP ?` — pas le tiret des mesures absentes, qui se lirait comme un
  capteur débranché alors que le trou est côté site et se comble avant de partir.
  Le même trou est annoncé en toutes lettres sur l'écran d'accueil
  (`ThresholdGap`, `account/threshold_gap.dart`), seul endroit où le cycliste a
  encore les mains libres. Les deux seuils arrivent **saisis ou estimés** — le
  site envoie sa valeur courante et sa source (`ftp.source`, `lthr_source`),
  celle-là même qui sert à ses propres zones, donc l'appli ne peut pas le
  contredire. Un bandeau sans zone cardio veut dire que le site n'a rien : ni
  saisie, ni sortie vélo au cardio dans sa fenêtre de 6 semaines.
  La mesure **et** sa zone sont peintes aux couleurs de la zone du moment
  (`ui/zone_colors.dart`, bleu Z1 → rouge Z5), cardio comme puissance, y compris
  dans le jeu « sortie » où les watts n'ont pas de case de zone à côté d'eux : à
  30 km/h on voit « du rouge » avant de déchiffrer « Z5 ». Aplats saturés et non
  teintés — sur le fond sombre du bandeau, cinq transparences donnent cinq gris —
  d'où le texte noir sur le jaune. **Une seule table pour les deux mesures** :
  `z4` est le seuil des deux côtés, deux palettes obligeraient à apprendre deux
  codes pour une seule sensation. La puissance prolonge simplement le dégradé
  au-delà du rouge, dans deux violets (`z6`, `z7`) que le cardio, trop lent, ne
  sait pas distinguer et n'atteint donc jamais.

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

### Le radar réveille l'écran

En veille (page web sous son voile, rétroéclairage à 1 %), le cadre et les
gouttières sont bien peints mais ne se voient pas — au soleil, pas du tout. Une
voiture qui remonte **rallume donc l'écran** et fait paraître `RadarWakePage`
(`ride/widgets/radar_wake_page.dart`) : les mètres en très gros sur du noir, avec
les gouttières et les pastilles par-dessus. La voiture passée, l'écran retourne
tout seul à 1 %.

- La décision est dans `RadarWakePolicy`, pure et testée, avec un **maintien de
  5 s** après extinction : un capteur qui hésite au bout de sa portée ferait
  sinon battre le rétroéclairage. Le maintien sert aussi à afficher la
  résolution — « Voie libre », qui dit *pourquoi* l'écran s'éteint. Radar perdu
  en pleine alerte, la page dit « Radar perdu » : `absent` n'est pas `clear`,
  et c'est ici qu'on le croirait le plus.
- L'arbitrage reste dans `ScreenPolicy` (`dimmed`, et `radarWake` pour
  l'affichage) : la demande de veille de la page est **retenue**, jamais
  annulée, donc la veille revient sans que la page ait à la redemander — elle
  n'a jamais su qu'on l'avait interrompue. Une page qui se réveille d'elle-même
  (virage) reprend l'écran et efface la page radar : c'est la carte qu'il faut
  alors regarder.
- La page radar **n'est pas dans le catalogue** `RidePage` : elle ne se fait pas
  défiler, ne prend aucun geste (le tap de réveil appartient à la page web), et
  s'arrête au-dessus du bandeau, qui garde ses mesures.

**Pour essayer le radar sans radar** : l'icône ◎ de la barre du haut, sur l'écran
des capteurs, ouvre `RadarDebugPage` — jusqu'à trois véhicules qui remontent en
boucle (`RadarSimulator`, pur et testé), avec la vitesse d'approche réglable.
Elle monte **les widgets de la sortie**, pas des copies : ce qu'on y voit et
entend est ce qui sortira sur la route. « Débrancher le radar » y coupe les
trames pour vérifier que la perte du capteur ne s'annonce pas comme une voie
libre, et « Simuler la veille » pose le voile noir pour juger le réveil radar de
bout en bout (le rétroéclairage, lui, ne bouge pas sur le banc).

## Calibrer un capteur de puissance

C'est le **seul endroit où l'appli écrit** sur un capteur : tout le reste est en
lecture. La procédure est *Start Offset Compensation* du Cycling Power Control
Point (0x2A66) — s'abonner aux indications, écrire `0x0C`, attendre la réponse ;
l'abonnement **d'abord**, sinon la plupart des capteurs refusent l'écriture,
n'ayant personne à qui répondre.

- Le protocole est isolé dans `ble/power_calibration.dart`, pur et testé.
  `calibrationResponseOf` rend `null` quand la trame ne nous concerne pas : le
  Control Point est partagé par toutes les procédures du profil, et la réponse
  d'une autre demande ne doit ni conclure ni faire échouer la nôtre. L'offset
  est **signé** — une jauge dérive dans les deux sens, et un sint16 lu en uint16
  sort un 65 000 absurde.
- `SensorConnection.calibratePower()` **ne lève jamais** : tout ressort en
  `PowerCalibrationResult`, parce que l'appelant est une boîte de dialogue
  ouverte au bord de la route. Le délai (15 s) est long à dessein, une jauge met
  plusieurs secondes à se stabiliser.
- La même boîte (`ui/power_calibration_dialog.dart`) sert **à l'arrêt et en
  sortie** : menu d'une ligne de la page Capteurs, et menu de la page Effort.
  C'est en roulant qu'on voit une puissance dériver ; s'il fallait quitter la
  navigation — donc perdre la carte et son démarrage — on finirait la sortie
  avec des watts faux.
- La commande n'apparaît que si `canCalibratePower` est vrai (le Control Point a
  été découvert) **et** le capteur connecté : un boîtier qui ne se calibre que
  par l'appli du constructeur ferait passer un refus de protocole pour une
  panne. La boîte prend une *fonction* et non une connexion, ce qui permet de la
  tester sans Bluetooth.
- Troisième entrée, la plus directe : **un tap sur les watts du bandeau**, ou sur
  leur case de zone — c'est là qu'on voit la puissance dériver, et non dans un
  menu deux pages plus loin. Celle-là ne filtre rien : la coquille ne se
  redessine pas quand le capteur finit sa découverte GATT, et un tap devenu
  inerte entre-temps se lirait comme un écran gelé. C'est donc
  `showPowerCalibrationFor` qui répond, avec un message par cas — « réveille-le »
  pour un capteur muet, « ça passe par l'appli du fabricant » pour un boîtier
  connecté sans Control Point, deux phrases qu'il ne faut pas confondre.

## Les capteurs du téléphone (`lib/phone/`)

Trois capteurs internes, un seul fichier de plateforme
(`android/…/PhoneSensors.kt`, un `EventChannel` par capteur). Pas de paquet :
`sensors_plus` ne couvre que la centrale inertielle, et les greffons qui
exposent le reste sont peu maintenus. **Chacun est facultatif** — un appareil
sans baromètre se comporte exactement comme avant.

- **Baromètre → dénivelé.** L'altitude GPS est bruitée de ±6 m, et ce bruit
  franchit l'hystérésis d'un mètre de `RideStats` à chaque oscillation : une
  heure de plat « gravissait » des centaines de mètres (le test le mesure). Le
  baromètre oscille de quelques centimètres, d'où un seuil dix fois plus fin
  (`baroAltitudeNoiseM`). Deux règles gardées par des tests :
  **le calage sur le GPS n'a lieu qu'une fois par sortie** — chaque recalage
  déplace tout le profil d'un coup et cette marche se compte comme du dénivelé —
  et **le GPS ne reprend jamais la main** une fois qu'une sortie a du baromètre,
  pas même sur les points où il manque, les deux sources étant décalées de
  plusieurs mètres. Le JSONL garde `balt` **et** `hpa` : la pression est la seule
  valeur irrécupérable, l'altitude dépend d'une référence.
- **Lumière → éclairage.** `AutoLightingPolicy` décidait sur la seule hauteur du
  soleil, qui ne sait rien d'un tunnel. Sous `nightLux` il fait nuit quoi qu'en
  dise le soleil, au-dessus de `dayLux` il fait jour ; **entre les deux la mesure
  ne tranche pas** et le soleil décide, comme avant. La nuit mesurée
  **court-circuite l'hystérésis** — un tunnel de 200 m se traverse en vingt
  secondes, on en serait sorti avant les 90 s de maintien — mais pas sa sortie :
  on entre dans la nuit sans délai, on en ressort avec le délai normal.
- **Boussole → cap à l'arrêt.** La course GPS se déduit du déplacement : **à
  l'arrêt elle n'existe pas** et la flèche de la page se figeait, au carrefour
  précisément. La boussole ne prend la main qu'à l'arrêt, et seulement après
  s'être **recoupée avec la course GPS en roulant** (`CompassHeading`) : un
  support aimanté sature le magnétomètre, qui indique alors le nord du support.
  L'écart moyen sert deux fois — il dit si la boussole est crédible, et il
  corrige un téléphone monté de travers. Moyenne **circulaire**, sinon 359° et 1°
  se moyennent à 180°. Le magnétomètre ne tourne que pendant la navigation
  (`RideShellPage` l'allume et l'éteint) ; il se nourrit de `recorder.lastFix`,
  donc **hors enregistrement il ne se validera pas** — même compromis assumé que
  le chien de garde du retour auto. Le cap traverse le pont (`headingDeg` dans la
  charge utile) et n'est publié **qu'à l'arrêt** : en roulant la page a sa propre
  course GPS, et deux sources feraient vibrer la flèche. Côté site, il est
  consommé par `updateBearing` (`RouteNavigation.vue`) — donc **les deux dépôts**.

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
JSONL garde ce que le `.fit` ne sait pas porter (positions Di2, précision GPS,
pression brute et altitude GPS quand le baromètre a pris le relais — le format
n'a qu'un seul champ d'altitude).

Les **calories** se déduisent du seul travail mécanique : `RideStats` cumule les
kJ (puissance × intervalle réel, plafonné pour qu'une pause ne crédite pas son
trou), et **kcal = kJ** — 1 kcal vaut 4,184 kJ, le rendement brut d'un cycliste
~24 %, donc le facteur est 1,00. Même convention que Garmin et Strava, sinon la
même sortie afficherait deux chiffres selon l'écran qui la montre. **Sans capteur
de puissance, il n'y a pas de calories** : la formule cardio de référence
(Keytel) demande l'âge et le sexe, que ni l'appli ni le site ne détiennent, et
sort ±20 % même bien nourrie. `total_calories` (champ 11 de `session` et de
`lap`) reste alors à l'invalide, et le site n'affiche pas sa pastille.

Le cadencement est régulier, pas déclenché par le GPS : à l'arrêt ou sous un
tunnel, la trace continue de porter le cardio et la puissance. Un point sans
position est une information, pas un trou.

## Se mettre à jour sans Play Store (`lib/update/`)

L'appli est diffusée par le site (`/companion`, réservé aux connectés) : **rien ne la
met à jour tout seul**. Sans contrôle, les téléphones divergent en silence jusqu'au
jour où le protocole du pont ne correspond plus entre les deux dépôts — ce qui se
manifeste par une navigation aux capteurs muets et pas un mot d'explication.

`UpdateChecker` interroge donc `/api/companion_version` **une fois par lancement**
(créé dans `SportsScopeApp`, pas dans l'accueil, qui se reconstruit à chaque retour de
sortie). Trois choses tenues par des tests :

- **L'ordre vient du `versionCode`, jamais du `versionName`** : en texte, « 0.10.0 »
  passe pour plus ancien que « 0.9.0 ». Et la comparaison est **strictement
  supérieure** — un `>=` proposerait éternellement la version qu'on vient
  d'installer, et un build de dev en avance sur la prod se verrait offrir un retour
  en arrière.
- **`CompanionRelease.parse` ne lève jamais**, même convention que les décodeurs
  GATT : le site peut être plus ancien que l'appli, renvoyer du HTML d'erreur ou un
  JSON amputé, et tout ça arrive dans un `initState`.
- **Un échec est muet.** Hors ligne avant de partir est le cas banal ; « le contrôle
  de version a échoué » n'est pas une information à poser sur l'écran d'avant-départ.
  Un seul état (`available == null`) pour « pas encore interrogé », « hors ligne »,
  « à jour » et « échec » : l'écran n'a qu'une carte à montrer ou non.

L'endpoint est **public** côté Rails, exprès : l'appli ne détient aucun cookie côté
Dart (la session vit dans le pot des WebViews), et passer par le WebView hors écran de
`RouteCatalogFetch` pour lire un numéro serait beaucoup de machinerie. Effet de bord
utile : le contrôle marche encore quand la session a expiré.

La carte ouvre la page **dans Chrome** (`url_launcher`, `externalApplication`) et non
dans un WebView : `webview_flutter` ne gère pas les téléchargements, c'est Chrome qui
détient la session du site, et c'est lui qu'Android enchaîne sur l'installateur.

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
- **`applicationId` et clé de signature sont définitifs.** Le paquet est
  `ch.logicraft.sports.companion` et la release se signe avec le keystore
  désigné par `android/key.properties` (hors dépôt, cf. `HOWTO.md`). Changer
  l'un ou l'autre après diffusion donne une application qu'Android tient pour
  étrangère : pas de mise à jour, désinstallation obligatoire, donc perte des
  capteurs appairés, de la session et des sorties non exportées. Un build de
  release sans clé **échoue** au lieu de retomber sur la clé de debug — ce repli
  est précisément le piège, puisqu'il ne se voit qu'à la mise à jour suivante.
  Le `+N` de `version:` (pubspec) est le `versionCode` : à incrémenter à chaque
  APK diffusé.
- L'App Link vérifié `https://` est déclaré dans le manifeste mais **inactif**
  tant que le site ne publie pas l'empreinte SHA-256 de la clé de release ; d'ici
  là le passage de session repose sur le schéma `sportsscope://` + un jeton à
  usage unique (voir les notes de sécurité de `HOWTO.md`). Côté Rails,
  `WellKnownController` ne sert qu'**un seul** paquet, celui du TWA : en faire
  cohabiter deux demande de toucher au dépôt voisin.
- Contre le serveur de dev, la connexion Keycloak ne peut pas aboutir depuis le
  téléphone (`keycloak.localtest.me` résout sur le téléphone lui-même). Tester
  la connexion contre la prod.
- `known_devices_store.dart` mentionne Drift dans un commentaire : **il n'y a
  pas de Drift dans le projet**, c'est un reste.
