/// Décodage de la position des vitesses d'un Di2 12 vitesses (R9250 / R8150 /
/// XTR M9200), service propriétaire `SHIMANO_BLE`.
///
/// Format non documenté par Shimano, établi par observation sur un groupe réel.
/// Trame de 17 octets, exemple (petit plateau, plus grand pignon) :
///
///   00 06 00 01 02 01 0C 00 00 00 06 EE 12 06 00 14 00
///               ^  ^  ^  ^
///               |  |  |  +-- offset 6 : nombre de pignons  (0C = 12)
///               |  |  +----- offset 5 : position pignon    (1..12)
///               |  +-------- offset 4 : nombre de plateaux (02)
///               +----------- offset 3 : position plateau   (1..2)
///
/// La trame encode donc **deux paires (position, nombre)**, ce qui explique du
/// même coup pourquoi l'offset 6 vaut exactement 12 sur un groupe 12 vitesses.
///
/// Convention : **la position 1 est le braquet le plus facile des deux côtés** —
/// petit plateau devant, plus grand pignon derrière. C'est la numérotation
/// naturelle du cycliste, et c'est aussi celle du format FIT (vérifié sur un
/// `.fit` de Geoid CC600 : `front_gear_num=1` porte 34 dents, `2` en porte 50 ;
/// `rear_gear_num=1` porte 36 dents). Positions et champs FIT s'exportent donc
/// tels quels, sans conversion.
///
/// Offsets encore inconnus : 15 (constant à 14 = 20, à croiser avec le Battery
/// Service). Aucun octet hors 3 et 5 n'a bougé lors des changements observés.
class Di2Gears {
  const Di2Gears({
    required this.frontPosition,
    required this.frontCount,
    required this.rearPosition,
    required this.rearCount,
    required this.raw,
  });

  /// 1 = petit plateau, [frontCount] = grand plateau.
  final int frontPosition;

  /// Nombre de plateaux annoncé par la trame (2 sur un double).
  final int frontCount;

  /// 1 = plus grand pignon, [rearCount] = plus petit.
  final int rearPosition;

  /// Nombre de pignons annoncé par la trame (12 sur un groupe 12v).
  final int rearCount;

  /// Trame brute, conservée telle quelle.
  final List<int> raw;

  static const frontOffset = 3;
  static const frontCountOffset = 4;
  static const rearOffset = 5;
  static const rearCountOffset = 6;
  static const minLength = 7;

  /// Décode une trame. Retourne `null` si elle est trop courte ou incohérente.
  ///
  /// Ne lève jamais : une trame non reconnue — firmware inattendu, notification
  /// tronquée — ne doit pas interrompre l'enregistrement d'une sortie. Le
  /// contenu brut reste disponible via [RawFrame] côté connexion.
  static Di2Gears? parse(List<int> data) {
    if (data.length < minLength) return null;

    final front = data[frontOffset];
    final frontCount = data[frontCountOffset];
    final rear = data[rearOffset];
    final rearCount = data[rearCountOffset];

    // Les compteurs valident les positions : plus besoin de coder en dur le
    // nombre de plateaux ou de pignons, la trame le dit.
    if (frontCount == 0 || front < 1 || front > frontCount) return null;
    if (rearCount == 0 || rear < 1 || rear > rearCount) return null;

    return Di2Gears(
      frontPosition: front,
      frontCount: frontCount,
      rearPosition: rear,
      rearCount: rearCount,
      raw: List.unmodifiable(data),
    );
  }

  bool get isBigChainring => frontPosition == frontCount;

  @override
  bool operator ==(Object other) =>
      other is Di2Gears &&
      other.frontPosition == frontPosition &&
      other.frontCount == frontCount &&
      other.rearPosition == rearPosition &&
      other.rearCount == rearCount;

  @override
  int get hashCode =>
      Object.hash(frontPosition, frontCount, rearPosition, rearCount);

  @override
  String toString() => '$frontPosition × $rearPosition/$rearCount';
}

// Les boutons satellites/sprinter (D-Fly) notifient sur une characteristic
// distincte de celle-ci, `0x2AC2` — voir `decoders/di2_buttons.dart`.

// Batterie des cocottes (leviers sans fil, pile CR1632 — pas la batterie
// principale du Di2, déjà lue via le Battery Service standard 0x2A19) :
// cherchée par sniff GATT complet (table entière des caractéristiques,
// lectures et écritures, capture HCI Bluetooth Android en mode « complet »
// pour ne rien tronquer) puis par corrélation d'une capture avec deux
// cocottes à niveaux connus (une quasi vide, une à 100 %) — sans succès.
//
// Ce qu'on sait : un service propriétaire distinct, `0x18FF` (même base
// vendeur `SHIMANO_BLE`, caractéristiques `0x2AF3`-`0x2AFF`), porte un
// protocole requête/réponse par appareil D-Fly — poignée de main sur
// `0x2AF3`/`0x2AF4`, puis lecture de « registres » (écriture sur `0x2AFA`
// ou `0x2AFE`, réponse en notification sur `0x2AF9`/`0x2AFD`) identifiés par
// un octet d'appareil (`0x00`/`0x0D` pour les deux leviers de l'essai) et une
// adresse. C'est ce protocole qu'utilise E-Tube derrière son bouton
// « Rafraîchir l'état » — qui exige d'appuyer physiquement sur chaque
// cocotte : la pile bouton ne répond que sur sollicitation, elle n'émet rien
// spontanément. Un octet candidat (nibble bas d'un registre à l'adresse
// `0x4118`) a semblé suivre l'écart de batterie sur un premier essai, puis
// l'a contredit sur un second (voir historique de session) : pas assez fiable
// pour un décodeur, laissé de côté plutôt que d'afficher un état faux.
//
// Aucune prior art publique trouvée non plus (recherche web, aucun projet
// open source ne documente ce protocole au niveau octet — les seuls efforts
// connus de rétro-ingénierie Di2 portent sur l'ANT+, jamais sur ce service
// BLE propriétaire). L'ANT+ privé de Shimano (utilisé par les compteurs type
// Garmin/Geoid) semble porter cette info directement — hors de portée du
// téléphone, qui n'a pas de radio ANT+.
//
// Si quelqu'un reprend ce chantier : il faudrait soit la doc Shimano, soit
// capturer plusieurs sessions à niveaux de batterie connus et bien espacés
// (pas juste vide/pleine) pour distinguer un vrai signal du bruit de trame.
