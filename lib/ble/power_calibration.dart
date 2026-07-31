/// La « mise à zéro » d'un capteur de puissance, côté protocole.
///
/// C'est la procédure *Start Offset Compensation* du Cycling Power Control
/// Point (0x2A66) : on écrit un octet, le capteur mesure sa jauge à vide et
/// répond son offset par une **indication**. Rien d'autre à envoyer — la valeur
/// est calculée et retenue par le capteur, l'appli ne fait que déclencher et
/// rendre compte.
///
/// Tout est ici et rien dans l'UI : c'est du décodage d'octets, ça se teste
/// sans Bluetooth, et c'est la seule partie où une erreur se voit mal (un
/// offset lu à l'envers ressemble à un offset).
library;

import 'dart:typed_data';

/// Déclenche la compensation d'offset (Start Offset Compensation).
const startOffsetCompensation = 0x0C;

/// Sa variante étendue, que certains capteurs implémentent seule. La réponse
/// porte l'offset au même endroit, suivi d'informations constructeur qu'on ne
/// lit pas.
const enhancedOffsetCompensation = 0x13;

/// Toute réponse du Control Point commence par cet octet ; les autres trames
/// qui passent par là sont des réponses à d'autres procédures.
const _responseCode = 0x20;

/// Ce que le capteur a répondu.
sealed class PowerCalibrationResult {
  const PowerCalibrationResult();

  /// À afficher tel quel : la boîte de dialogue n'a pas à traduire des codes.
  String get message;
}

/// Calibration acceptée. [offset] est la valeur brute rendue par le capteur —
/// sans unité commune d'un constructeur à l'autre, elle ne sert qu'à comparer
/// deux calibrations du même capteur, et à voir qu'il a vraiment répondu.
class PowerCalibrationDone extends PowerCalibrationResult {
  const PowerCalibrationDone({this.offset});

  final int? offset;

  @override
  String get message =>
      offset == null ? 'Capteur calibré.' : 'Capteur calibré · offset $offset';
}

/// Pourquoi la calibration n'a pas eu lieu.
///
/// La distinction qui compte est entre « le capteur a dit non » et « personne
/// n'a répondu » : le premier est définitif, le second se retente.
enum PowerCalibrationError {
  /// Capteur absent ou déconnecté au moment du geste.
  notConnected,

  /// Pas de Control Point sur cet appareil : il ne sait pas se calibrer par
  /// BLE, il faut passer par l'appli du constructeur ou une manœuvre de
  /// pédale.
  notSupported,

  /// Control Point présent, mais la procédure refusée.
  refused,

  /// Le capteur a essayé et échoué — typiquement une jauge sous charge : un
  /// pied sur la pédale, un vélo pas d'aplomb.
  failed,

  /// Rien n'est revenu dans le délai. Le capteur s'est peut-être endormi.
  noAnswer,
}

class PowerCalibrationFailed extends PowerCalibrationResult {
  const PowerCalibrationFailed(this.error, {this.detail});

  final PowerCalibrationError error;

  /// Le détail technique, quand il y en a un (exception, code inattendu). Il
  /// s'ajoute au message : sans lui, un refus reste indébogable sur la route.
  final String? detail;

  @override
  String get message {
    final base = switch (error) {
      PowerCalibrationError.notConnected =>
        'Capteur de puissance non connecté.',
      PowerCalibrationError.notSupported =>
        'Ce capteur ne se calibre pas par Bluetooth.',
      PowerCalibrationError.refused => 'Calibration refusée par le capteur.',
      PowerCalibrationError.failed => 'Le capteur n\'a pas pu se calibrer. '
          'Vérifie que le vélo est à l\'arrêt, pédales libres.',
      PowerCalibrationError.noAnswer =>
        'Le capteur n\'a pas répondu. Réveille-le en tournant les manivelles, '
            'puis réessaie.',
    };
    return detail == null ? base : '$base ($detail)';
  }
}

/// Lit une trame du Control Point.
///
/// Renvoie `null` quand la trame **ne nous concerne pas** : le Control Point
/// est partagé par toutes les procédures du profil (longueur de manivelle,
/// position du capteur…), et la réponse d'une autre demande ne doit ni
/// conclure ni faire échouer la nôtre. Ne lève jamais — même contrat que les
/// décodeurs.
PowerCalibrationResult? calibrationResponseOf(List<int> data) {
  // [0x20][opcode demandé][valeur de réponse][paramètres…]
  if (data.length < 3) return null;
  if (data[0] != _responseCode) return null;
  if (data[1] != startOffsetCompensation &&
      data[1] != enhancedOffsetCompensation) {
    return null;
  }

  return switch (data[2]) {
    0x01 => PowerCalibrationDone(offset: _offsetOf(data)),
    0x02 =>
      const PowerCalibrationFailed(PowerCalibrationError.notSupported),
    0x03 => const PowerCalibrationFailed(PowerCalibrationError.refused,
        detail: 'paramètre invalide'),
    0x04 => const PowerCalibrationFailed(PowerCalibrationError.failed),
    final other => PowerCalibrationFailed(PowerCalibrationError.refused,
        detail: 'code 0x${other.toRadixString(16)}'),
  };
}

/// L'offset renvoyé avec un succès : sint16 petit-boutiste, juste après la
/// valeur de réponse. **Signé** — une jauge dérive dans les deux sens, et un
/// offset négatif lu comme un uint16 sortirait un 65 000 absurde.
///
/// Absent chez certains capteurs, qui se contentent d'acquitter : on rend
/// `null` plutôt que zéro, qui est un offset parfaitement valide.
int? _offsetOf(List<int> data) {
  if (data.length < 5) return null;
  return ByteData.sublistView(Uint8List.fromList(data)).getInt16(3, Endian.little);
}
