import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Fabrique les tonalités d'alerte dans `assets/sounds/` : celles du radar
/// arrière, celle du filet natif de virages (`native_turn_alerts.dart`),
/// celles du composant `bell` du tableau de bord (`bell_block.dart`), et
/// celle d'une batterie faible (`battery_alert_sound.dart`).
///
/// Les sons sont *générés* et non téléchargés, pour trois raisons : ils pèsent
/// quelques kilo-octets, ils n'ont aucune licence à traîner, et surtout ils
/// restent **réglables** — changer une fréquence ou une durée ici et relancer le
/// script vaut mieux que de chercher un fichier qui sonne à peu près bien.
///
/// ```bash
/// dart run tool/radar_tones.dart
/// ```
///
/// Le vocabulaire est volontairement lisible sans les entendre :
///
/// - **approche** : un bip grave et court. Quelque chose est là, rien d'urgent.
/// - **proche** : deux bips aigus. Plus haut, plus répété — les deux dimensions
///   que l'oreille lit comme « ça se rapproche », sans avoir à l'apprendre.
/// - **dégagé** : deux notes *descendantes*. Une descente ne s'entend jamais
///   comme une alerte ; c'est ce qui la rend impossible à confondre avec les
///   deux autres, même mal entendue dans le vent.
/// - **virage** (filet natif) : quatre bips identiques, plus aigus et à plein
///   gain — c'est la seule alerte de l'appli qui ne peut compter sur aucun
///   rattrapage visuel (l'écran est verrouillé quand elle sonne), elle doit
///   donc percer le vent mieux que les autres. Pas de mélodie à apprendre,
///   juste le même signal répété pour qu'on le reconnaisse même à moitié
///   entendu sous un casque.
/// - **sonnette** (`bell`) : trois notes aiguës brèves, le repli du composant
///   `bell` — un tintement de sonnette de vélo, pas une alerte de conduite,
///   qu'on reconnaît d'un coup de pouce délibéré et non d'un capteur.
/// - **batterie faible** (`battery_low`) : deux notes graves qui retombent
///   lentement — grave et lent pour ne jamais se confondre avec les deux
///   notes aiguës et brèves de « dégagé » (`radar_clear`), ni avec aucune
///   autre alerte de ce fichier. Une retombée, pas une alarme : ce n'est pas
///   un danger immédiat, juste quelque chose à savoir avant que ça le
///   devienne.
/// - **klaxon** (`horn`) : un accord de trois trompes graves tenues ensemble,
///   avec une attaque longue — la montée en pression qu'on entend sur un
///   vrai avertisseur pneumatique à trompes (celui des voitures de la
///   caravane du Tour de France), pas le claquage nul instantané d'un signal
///   électronique. Grave et battant, à l'opposé de tous les bips aigus
///   ci-dessus. Le but n'est pas seulement d'être fort mais de ne **jamais**
///   se confondre avec une alerte radar ou virage entendue par erreur.
///
/// Chaque note porte une deuxième harmonique : une sinusoïde pure est propre en
/// intérieur et disparaît à 30 km/h. Et chaque note a ses fondus d'attaque et
/// d'extinction — sans eux, la coupure nette du signal s'entend comme un clic.
/// Le fondu d'attaque est réglable par note (`attackMs`) : bref partout sauf
/// sur `horn`, où il devient la montée en pression de la trompe. `bell`/`horn`
/// jouent en boucle (`ReleaseMode.loop`) : le silence en fin de notes sert
/// aussi de respiration entre deux tours de boucle.
void main(List<String> args) {
  final directory = Directory('assets/sounds')..createSync(recursive: true);

  _write(directory, 'radar_approach.wav', [
    const _Note(hz: 700, ms: 120),
  ]);

  _write(directory, 'radar_close.wav', [
    const _Note(hz: 1100, ms: 90),
    const _Note.silence(ms: 70),
    const _Note(hz: 1100, ms: 90),
  ]);

  _write(directory, 'radar_clear.wav', [
    const _Note(hz: 880, ms: 80, gain: 0.6),
    const _Note(hz: 587, ms: 110, gain: 0.6),
  ]);

  _write(directory, 'battery_low.wav', [
    const _Note(hz: 330, ms: 180, gain: 0.7),
    const _Note.silence(ms: 90),
    const _Note(hz: 220, ms: 260, gain: 0.7),
  ]);

  _write(directory, 'turn_alert.wav', [
    const _Note(hz: 1600, ms: 150, gain: 1),
    const _Note.silence(ms: 100),
    const _Note(hz: 1600, ms: 150, gain: 1),
    const _Note.silence(ms: 100),
    const _Note(hz: 1600, ms: 150, gain: 1),
    const _Note.silence(ms: 100),
    const _Note(hz: 1600, ms: 150, gain: 1),
  ]);

  _write(directory, 'bell.wav', [
    const _Note(hz: 1760, ms: 130, gain: 1),
    const _Note.silence(ms: 60),
    const _Note(hz: 1760, ms: 130, gain: 1),
    const _Note.silence(ms: 60),
    const _Note(hz: 1760, ms: 130, gain: 1),
    const _Note.silence(ms: 260),
  ]);

  // Les trois trompes ensemble, pas en fanfare : un accord tenu, avec une
  // attaque de 180 ms — la pression qui monte dans les trompes avant que le
  // son parte plein volume, contre les 6 ms « clic » de toutes les autres
  // tonalités du fichier.
  _write(directory, 'horn.wav', [
    const _Note(hz: 294, hz2: 370, hz3: 440, ms: 780, gain: 1, attackMs: 180),
    const _Note.silence(ms: 500),
  ]);
}

const _sampleRate = 44100;

/// Durée des fondus d'entrée et de sortie de chaque note.
const _fadeMs = 6;

class _Note {
  const _Note({
    required this.hz,
    required this.ms,
    this.gain = 0.85,
    this.hz2,
    this.hz3,
    this.attackMs,
  });

  const _Note.silence({required this.ms})
      : hz = 0,
        hz2 = null,
        hz3 = null,
        gain = 0,
        attackMs = null;

  final double hz;

  /// Une deuxième, puis une troisième fréquence jouées en même temps que
  /// [hz] — l'accord des trois trompes du klaxon (`horn.wav`), plus grave et
  /// plus riche qu'un ton pur. `null` pour toutes les autres tonalités : une
  /// seule note.
  final double? hz2;
  final double? hz3;

  final int ms;
  final double gain;

  /// Fondu d'attaque propre à cette note, en ms — `null` reprend [_fadeMs],
  /// le clic bref de toutes les autres tonalités. Le klaxon en a besoin d'un
  /// plus long : la montée en pression d'un avertisseur pneumatique s'entend,
  /// ce n'est pas un signal électronique qui claque plein volume d'un coup.
  final int? attackMs;
}

void _write(Directory directory, String name, List<_Note> notes) {
  final samples = <double>[];
  for (final note in notes) {
    samples.addAll(_render(note));
  }

  final file = File('${directory.path}/$name');
  file.writeAsBytesSync(_wav(samples));
  stdout.writeln('${file.path} — ${samples.length ~/ (_sampleRate ~/ 1000)} ms, '
      '${file.lengthSync()} octets');
}

List<double> _render(_Note note) {
  final count = _sampleRate * note.ms ~/ 1000;
  final attack = math.min(_sampleRate * (note.attackMs ?? _fadeMs) ~/ 1000, count ~/ 2);
  final release = math.min(_sampleRate * _fadeMs ~/ 1000, count ~/ 2);
  final tones = [note.hz, if (note.hz2 != null) note.hz2!, if (note.hz3 != null) note.hz3!];

  return [
    for (var i = 0; i < count; i++)
      if (note.hz == 0)
        0.0
      else
        _envelope(i, count, attack, release) *
            note.gain *
            // La moyenne des tons (un seul, d'habitude) : diviser par leur
            // nombre garde `horn.wav` (trois tons) au même gabarit que les
            // notes à un seul ton, sans écrêter.
            (tones.map((hz) => _tone(hz, i)).reduce((a, b) => a + b) / tones.length),
  ];
}

// Fondamentale plus une deuxième harmonique discrète : c'est elle qui fait
// passer le son par-dessus le bruit du vent.
double _tone(double hz, int i) =>
    0.8 * math.sin(2 * math.pi * hz * i / _sampleRate) +
    0.2 * math.sin(4 * math.pi * hz * i / _sampleRate);

double _envelope(int i, int count, int attack, int release) {
  if (attack > 0 && i < attack) return i / attack;
  if (release > 0 && i >= count - release) return (count - i) / release;
  return 1;
}

/// PCM 16 bits, mono, 44,1 kHz — le format que tout lit sans se poser de
/// question.
Uint8List _wav(List<double> samples) {
  final data = ByteData(44 + samples.length * 2);
  var offset = 0;

  void ascii(String value) {
    for (final unit in value.codeUnits) {
      data.setUint8(offset++, unit);
    }
  }

  void uint32(int value) {
    data.setUint32(offset, value, Endian.little);
    offset += 4;
  }

  void uint16(int value) {
    data.setUint16(offset, value, Endian.little);
    offset += 2;
  }

  ascii('RIFF');
  uint32(36 + samples.length * 2);
  ascii('WAVE');
  ascii('fmt ');
  uint32(16); // taille du bloc de format
  uint16(1); // PCM
  uint16(1); // mono
  uint32(_sampleRate);
  uint32(_sampleRate * 2); // octets par seconde
  uint16(2); // alignement de bloc
  uint16(16); // bits par échantillon
  ascii('data');
  uint32(samples.length * 2);

  for (final sample in samples) {
    data.setInt16(
      offset,
      (sample.clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
    offset += 2;
  }

  return data.buffer.asUint8List();
}
