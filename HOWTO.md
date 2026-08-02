# Connexion au téléphone
- Sur le téléphone deboggage sans fil -> associer l'appareil avec un code d'association
- dans WSL: adb pair <ip téléphone>:<port de l'association>
- ensuite adb connect <ip téléphone>:<port de debug> (pas le même port, le port est dans la page principale du telephone pas dans l'association
- l'appairage n'est pas à refaire il faut juste se reconnecter

#Pour lancer l'application (debug)
- cd ~/dev/sports-scope-companion
- flutter run

# Appairer un capteur

L'écran d'accueil ne montre des capteurs que **l'essentiel** : une icône par
capteur appairé, **verte s'il répond, orange sinon**. C'est la seule chose qu'on
regarde avant de partir — la ceinture est-elle réveillée, le compteur de
puissance est-il sorti de veille.

Un capteur **gris et barré** est un capteur dont on a coupé la connexion
automatique (menu de sa ligne, page Capteurs) : il n'est pas en panne, il est
mis de côté, et l'appli n'ira pas le chercher. C'est le réglage à vérifier en
premier quand un capteur « ne se connecte plus ».

Le reste est derrière cette carte (ou l'icône capteurs, barre du haut) : la page
**Capteurs**, avec *Mes capteurs* et *Appareils détectés*. On y va pour appairer
un capteur neuf — bouton **Scanner** de la barre du haut, puis tap sur la ligne
qui apparaît — pour en oublier un, ou pour couper la connexion automatique d'un
capteur prêté. L'appairage se fait une fois ; ensuite, les capteurs connus se
rattachent seuls dès que le Bluetooth est allumé.

Un capteur qui dort (typiquement un capteur de puissance, qui se rendort dès que
les manivelles s'arrêtent) peut mettre du temps à revenir : l'appli cherche
toute seule, par courtes salves, **tant qu'il manque un capteur** — et s'arrête
de chercher dès que tout est connecté. Réveiller le capteur (quelques tours de
manivelle) le fait attraper dans les secondes qui suivent. Un capteur dont la
**connexion automatique est désactivée** n'est jamais rattrapé ainsi : c'est
tout l'intérêt du réglage.

Un appareil n'entre dans *Mes capteurs* qu'une fois qu'il a **répondu** : tant
qu'il se connecte, il reste sous *Connexion en cours*. Les *trames brutes*, en
bas de page, sont l'outil de reverse — un capteur qui n'y écrit rien est un
capteur muet, pas un décodeur en panne.

## Choisir son profil de sortie

Les profils se règlent **sur le site** et se choisissent **dans l'appli, au
départ** : on sait sur quel vélo on monte au moment où l'on monte dessus.

Tape **Naviguer** : la feuille qui s'ouvre commence par une ligne
**« Profil : … »**, avec le nombre de pages et ce que le profil coupe (« sans
carte », « sans GPS », « sans radar »). Tape-la pour en changer. Le choix est
retenu jusqu'à ce que tu en changes — y compris pour un enregistrement lancé
depuis l'accueil, qui part avec les mêmes capteurs.

La ligne **n'apparaît que s'il y a plusieurs profils**. Tant que le compte n'a
rien de réglé, le site en sert trois : *Route*, *VTT* et *Home-trainer*.

Ce qu'un profil décide :

- **les pages du tableau de bord** — combien, dans quel ordre, et ce qu'il y a
  dans chacune (une grille de mesures, une page qui défile, la carte) ;
- **les jeux de valeurs du bandeau du bas** (quatre cases au plus par jeu) ;
- **les capteurs utilisés.** Le profil *Home-trainer* coupe le GPS : pas de
  notification de service au premier plan, pas de « Recherche du GPS… » au
  démarrage, et distance et dénivelé affichent un tiret plutôt qu'un zéro. Il
  coupe aussi le radar et le baromètre, et **n'a pas de carte du tout** — la
  feuille de départ se réduit alors au profil et à un bouton *Démarrer*.

Un capteur qu'un profil écarte n'est pas déconnecté pour autant : s'il est déjà
connecté, il continue de mesurer. Le profil décide seulement de ce que l'appli va
*chercher*. Et il ne peut jamais **rendre** la connexion automatique à un capteur
que tu as décoché à la main : ton geste gagne.

Hors ligne, l'appli garde les derniers profils reçus. Sur une installation neuve
sans réseau, elle ouvre son tableau de bord intégré — carte plus page Effort,
exactement comme avant les profils.

## Calibrer le capteur de puissance

La mise à zéro d'un capteur de puissance (compensation d'offset) se lance de
**deux endroits** : le menu de sa ligne dans *Mes capteurs*, et le menu ⋮ de la
page **Effort** pendant la sortie — c'est en roulant qu'on voit des watts
douteux, et la navigation n'a pas à être quittée pour ça.

Dans les deux cas : **vélo à l'arrêt et d'aplomb, rien qui appuie sur les
pédales**, et on n'y touche plus pendant la mesure. Le capteur répond en
quelques secondes, avec son offset — une valeur brute, sans unité comparable
d'une marque à l'autre, utile pour comparer deux calibrations du même capteur.

La commande n'apparaît que si le capteur est connecté **et** sait se calibrer
par Bluetooth (Control Point du profil Cycling Power). Beaucoup de capteurs
n'exposent rien : ceux-là se calibrent depuis l'appli du constructeur, ou par la
manœuvre de pédale de leur mode d'emploi. Un « le capteur n'a pas pu se
calibrer » vient presque toujours d'une jauge sous charge — un pied resté sur la
pédale suffit.

# Se connecter au site

## Le chemin normal : depuis le site, en un tap

Connecté sur sports.logicraft.ch dans Chrome, sur la page de partage d'un
itinéraire, **« Naviguer dans l'application »** ouvre l'appli *déjà connectée au
même compte*. Rien à retaper.

Ça ne va pas de soi : Chrome et le WebView de l'appli ont deux pots de cookies
distincts. Au tap, la page demande donc au serveur un **jeton de passage** — à
usage unique, valable 5 minutes — et le joint au lien. L'appli ouvre alors
`/auth/handoff?token=…&next=…`, que Rails échange contre une vraie session avant
d'afficher la navigation (`SessionHandoff`, `SessionsController#handoff` côté
serveur). Le jeton est demandé au tap et pas au rendu de la page : une page de
partage peut rester ouverte bien plus longtemps qu'il ne vit.

L'appli ne fait que transmettre ce jeton — elle ne voit ni mot de passe, ni
identifiant, et n'en stocke aucun.

Si le jeton échoue (hors ligne, jeton périmé, lien recopié à la main), la
navigation s'ouvre quand même, en anonyme : elle est publique. Le transfert de
session est un confort, jamais une condition.

## L'autre chemin : l'écran Compte

L'icône **Compte** (barre du haut) ouvre le site dans un WebView : on s'y
connecte comme dans un navigateur, par Keycloak. Utile quand on démarre depuis
l'appli plutôt que depuis un lien. C'est à faire **une fois** — le cookie de
session dure 30 jours et Android le garde sur le disque.

Tous les WebViews de l'appli partagent le même pot de cookies : se connecter ici
authentifie donc aussi la navigation, sans que le code Dart ait à transmettre
quoi que ce soit. L'appli ne retient que « connecté / pas connecté », pour
pouvoir l'afficher sans ouvrir de page.

## Ce qu'on perd en anonyme

Tant qu'on n'est pas connecté, la navigation s'ouvre quand même, mais en mode
anonyme — et **quatre choses tombent en même temps** :

- pas d'itinéraires sauvegardés dans « Naviguer vers un itinéraire »
  (`/api/routes` demande une session) ;
- le fond de carte est celui par défaut, pas celui du profil (il vient de la
  balise `<meta name="user-preferences">`, rendue aux seuls connectés) ;
- le menu POI ne renvoie rien (`/api/geocode/places` demande une session) ;
- les POI enregistrés (`/api/pois`) n'apparaissent pas.

Le bandeau orange de l'écran d'accueil le signale avant de partir.

## Notes

Sécurité : sur Android, un lien `sportsscope://` peut être capté par n'importe
quelle appli qui déclare le même schéma — d'où un jeton à usage unique et de
courte durée. La parade complète est l'**App Link vérifié** (lien `https://`, que
seule l'appli signée par la bonne clé peut recevoir) : l'intent-filter est déjà
déclaré dans le manifeste, il s'active dès que
`https://sports.logicraft.ch/.well-known/assetlinks.json` publie le nom de
paquet et l'empreinte SHA-256 de signature (variables `ANDROID_PACKAGE_NAME` /
`ANDROID_CERT_FINGERPRINTS` côté serveur). Le paquet porte désormais son nom
définitif (`ch.logicraft.sports.companion`), donc plus rien ne s'y oppose : il
reste à publier l'empreinte de la clé de release (voir plus bas), en notant que
le serveur ne sert aujourd'hui **qu'un seul** paquet — celui du TWA. Faire
cohabiter les deux demande d'étendre `WellKnownController` côté Rails.

Dev : contre le serveur de dev, Keycloak est publié sur
`keycloak.localtest.me`, qui résout sur `127.0.0.1` — donc sur le *téléphone*
lui-même. La connexion ne peut pas aboutir depuis l'appareil avec un
`--dart-define=SPORTS_SCOPE_URL=http://<ip du poste>:3000` ; contre la prod (la
cible par défaut) elle fonctionne.

# Enregistrer une sortie

Trois façons de lancer une sortie. Le bandeau **Enregistrement**, en haut de
l'écran d'accueil. Si vous partez en navigation sans avoir rien lancé, l'appli
**pose la question avant d'ouvrir la carte** : « Enregistrer cette sortie ? ». Et
si vous avez répondu *Naviguer seulement*, la page **Effort** du tableau de bord
garde en tête un bouton **Démarrer l'enregistrement**, tant que rien ne tourne.

Ce qui précède le démarrage n'est en revanche jamais rattrapé : une sortie lancée
au bout de dix kilomètres commence au dixième kilomètre. Le démarrage n'est pas
automatique pour autant — ouvrir la carte deux minutes pour vérifier une route
fabriquerait une sortie à chaque fois. Si le GPS se dérobe au moment de démarrer,
l'appli le dit et ouvre la navigation quand même.

La page Effort sait aussi **suspendre et reprendre** : le bouton *Mettre en
pause* est discret, et la reprise prend la forme d'un bandeau orange sur toute la
largeur — une pause oubliée est la seule façon de perdre la fin d'une sortie sans
s'en apercevoir, les compteurs figés se lisant aussi bien comme « en pause » que
comme « arrêté à un feu ».

Rien pour **terminer**, en revanche : ça se fait au retour, depuis l'écran
d'accueil. Une pause ne coûte rien et se défait d'un tap ; un bouton qui clôt la
sortie, à portée de pouce sur une page qu'on consulte en roulant, coûterait un
jour une sortie entière.

Pour **revenir à l'accueil**, le menu ⋮ de la page Effort porte *Revenir à
l'accueil*, tout en bas. Le bouton retour du téléphone y mène aussi, sans rien
demander : il ramène d'abord sur la carte, puis sort. L'accueil affiche alors en
tête *Reprendre la navigation* — un tap et la carte rouvre là où on en était,
tracé et progression compris. L'enregistrement, lui, n'a pas bougé pendant ce
temps.

Démarrer demande la position (et, sur Android 13+, l'autorisation de notifier),
puis écrit un point par seconde : position, altitude, vitesse GPS, plus le
cardio, la puissance, la cadence et les vitesses Di2 des capteurs connectés à ce
moment-là. La sortie continue quand on passe en navigation, écran éteint ou
appli en arrière-plan — c'est le rôle du service au premier plan, signalé par sa
notification persistante.

- **Pause** fige le chronomètre et la distance ; le GPS reste accroché.
- **Terminer** clôt la sortie. Rien n'est perdu si l'appli meurt avant :
  la sortie apparaît alors comme « interrompue » et reste exportable.

Les sorties sont dans **Mes sorties** (icône itinéraire, barre du haut) :
`Exporter en .fit` construit le fichier et ouvre le partage d'Android. De là,
le `.fit` se dépose dans la page d'import de sports-scope.

## Où sont les données

Sur le téléphone, dans le dossier applicatif :

```
rides/2026-07-28T14-03-11Z/session.json   ← le résumé (durée, distance, points)
rides/2026-07-28T14-03-11Z/points.jsonl   ← un point par ligne, écrit en ajout
```

Pour les récupérer en debug :

```bash
adb exec-out run-as ch.logicraft.sports.companion \
  tar c files/rides > rides.tar
```

Le `.fit` est reconstruit à partir du JSONL à chaque export : réexporter est
sans risque, et le JSONL garde ce que le format `.fit` ne sait pas porter
(positions Di2, précision GPS).

## Vérifier un `.fit`

Les tests Dart (`test/fit_writer_test.dart`) relisent les octets produits ; pour
vérifier qu'un lecteur *tiers* en tire les bonnes valeurs, on passe par
`fit-file-parser`, celui qu'utilise la page d'import du site :

```bash
dart run tool/fit_sample.dart /tmp/sortie.fit
node -e '
  const fs = require("fs");
  const FitParser = require("'"$HOME"'/dev/sports-scope/node_modules/fit-file-parser").default;
  const buf = fs.readFileSync("/tmp/sortie.fit");
  // force: false → les CRC sont vérifiés, un fichier mal formé échoue.
  new FitParser({ force: false, mode: "list", speedUnit: "m/s", lengthUnit: "m" })
    .parse(buf.buffer, (err, data) => {
      if (err) throw err;
      console.log(data.records.length, "points ·", JSON.stringify(data.sessions[0]));
    });
'
```

# Construire un APK à distribuer

## Une fois pour toutes : la clé de signature

Android identifie une application par son **applicationId** *et* sa **clé de
signature**. Les deux sont définitifs : changer l'un ou l'autre après diffusion
donne une application que le téléphone tient pour étrangère, qui refuse de se
mettre à jour par-dessus l'ancienne. Il faut alors désinstaller — donc perdre les
capteurs appairés, la session du site et les sorties non exportées.

Créer le keystore, **hors du dépôt** :

```bash
keytool -genkeypair -v \
  -keystore ~/.keys/sports-scope-companion.jks \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias companion
```

Puis `android/key.properties` sur le modèle de `android/key.properties.example`
(les deux fichiers sensibles, `.jks` et `key.properties`, sont ignorés par git) :

```properties
storeFile=/home/<vous>/.keys/sports-scope-companion.jks
storePassword=…
keyAlias=companion
keyPassword=…
```

**Sauvegarder le `.jks` et son mot de passe ailleurs que sur la machine de
build.** Les perdre, c'est ne plus jamais pouvoir mettre à jour les APK déjà
installés : la seule issue serait de rebâtir sous un autre applicationId, donc de
faire désinstaller tout le monde.

Sans `key.properties`, un build de release **échoue** au lieu de retomber sur la
clé de debug (`android/app/build.gradle.kts`) : un APK signé debug s'installe et
se distribue sans rien signaler, et le piège ne se referme qu'à la mise à jour
suivante.

## « Application non installée » : c'est presque toujours la signature

`flutter run` installe un build signé de la **clé de debug**, sous le même
`applicationId` que la release. Les deux ne peuvent pas cohabiter : dès qu'un build de
debug est sur l'appareil, l'APK de release refuse de s'installer par-dessus, et
l'écran d'Android se contente d'« application non installée » sans dire pourquoi. Ce
n'est **pas** Play Protect, qui se traverse par « Installer quand même ».

Pour lire la vraie raison, passer par `adb` plutôt que par l'écran :

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
# INSTALL_FAILED_UPDATE_INCOMPATIBLE → conflit de signature, voir ci-dessous
```

Comparer les deux signatures — celle qui est installée et celle de l'APK :

```bash
adb shell dumpsys package ch.logicraft.sports.companion | grep -i "^ *Signatures"
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk | grep SHA-256
```

Si elles diffèrent, désinstaller d'abord — en sauvant les sorties s'il y en a
(cf. « Où sont les données ») :

```bash
adb uninstall ch.logicraft.sports.companion   # tous les profils
```

**Chercher le paquet dans tous les profils.** `dumpsys` donne un bloc `User N:` par
profil : un Pixel avec un espace privé peut porter l'app dans le profil 10 alors que
`installed=false` dans le profil 0. Elle n'apparaît nulle part sur l'écran d'accueil
principal, et bloque quand même l'installation.

## Construire

Incrémenter d'abord le `+N` de `version:` dans `pubspec.yaml` — c'est le
`versionCode`, et Android refuse d'installer par-dessus un numéro supérieur ou
égal, avec un « application non installée » qui ne dit pas pourquoi.

```bash
flutter build apk --release --target-platform android-arm64
# → build/app/outputs/flutter-apk/app-release.apk  (~15–20 Mo)
```

`android-arm64` couvre tous les téléphones du marché depuis ~2016 et divise le
fichier par deux ou trois par rapport à l'APK universel. Pour un doute sur un
appareil ancien, `flutter build apk --release` sans option produit l'universel.

Vérifier la signature avant d'envoyer le fichier :

```bash
$ANDROID_HOME/build-tools/*/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

Le `SHA-256` affiché est **l'empreinte à publier** dans
`ANDROID_CERT_FINGERPRINTS` côté Rails pour activer l'App Link vérifié
(cf. les notes de sécurité plus haut).

## Publier sur le site

Le site distribue l'APK à ses membres (`https://sports.logicraft.ch/companion`,
réservé aux connectés). La publication se fait depuis le dépôt Rails voisin, sans
redéployer le site :

```bash
cd ~/dev/sports-scope
script/push-apk.sh          # prend build/app/outputs/flutter-apk/app-release.apk
```

Le script relit l'APK avant d'envoyer quoi que ce soit — nom de paquet, signature,
`versionCode` — affiche ce qu'il s'apprête à publier, et demande confirmation. Il lit
la version **dans le fichier** et non dans `pubspec.yaml` : c'est l'APK publié qui
fait foi, un pubspec modifié après le build annoncerait une version que personne n'a
téléchargée.

Côté téléphones déjà équipés, rien ne se met à jour tout seul : l'app interroge
`/api/companion_version` **une fois par lancement** et, si le `versionCode` publié est
supérieur au sien, pose une carte sur l'écran d'accueil qui ouvre la page de
téléchargement dans Chrome (`lib/update/`). Hors ligne ou déjà à jour, elle ne dit
rien.
