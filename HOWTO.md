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

Le reste est derrière cette carte (ou l'icône capteurs, barre du haut) : la page
**Capteurs**, avec *Mes capteurs* et *Appareils détectés*. On y va pour appairer
un capteur neuf — bouton **Scanner** de la barre du haut, puis tap sur la ligne
qui apparaît — pour en oublier un, ou pour couper la connexion automatique d'un
capteur prêté. L'appairage se fait une fois ; ensuite, les capteurs connus se
rattachent seuls dès que le Bluetooth est allumé, sans scan.

Un appareil n'entre dans *Mes capteurs* qu'une fois qu'il a **répondu** : tant
qu'il se connecte, il reste sous *Connexion en cours*. Les *trames brutes*, en
bas de page, sont l'outil de reverse — un capteur qui n'y écrit rien est un
capteur muet, pas un décodeur en panne.

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
`ANDROID_CERT_FINGERPRINTS` côté serveur). Tant que le paquet s'appelle
`com.example.sports_scope_companion`, ce n'est pas fait.

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
adb exec-out run-as com.example.sports_scope_companion \
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
