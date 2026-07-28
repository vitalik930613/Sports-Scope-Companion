# Connexion au téléphone
- Sur le téléphone deboggage sans fil -> associer l'appareil avec un code d'association
- dans WSL: adb pair <ip téléphone>:<port de l'association>
- ensuite adb connect <ip téléphone>:<port de debug> (pas le même port, le port est dans la page principale du telephone pas dans l'association
- l'appairage n'est pas à refaire il faut juste se reconnecter

#Pour lancer l'application (debug)
- cd ~/dev/sports-scope-companion
- flutter run

# Enregistrer une sortie

Le bandeau **Enregistrement** est en haut de l'écran des capteurs. Démarrer
demande la position (et, sur Android 13+, l'autorisation de notifier), puis
écrit un point par seconde : position, altitude, vitesse GPS, plus le cardio, la
puissance, la cadence et les vitesses Di2 des capteurs connectés à ce
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
