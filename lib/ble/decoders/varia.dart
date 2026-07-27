import '../samples.dart';

/// Décodage des cibles du radar arrière Garmin Varia (RTL5xx / RCT7xx).
///
/// ⚠️ **Disposition non confirmée sur ton matériel.** Garmin ne publie aucune
/// spec ; ce qui suit reflète ce que la communauté a observé, et non une trame
/// que j'aurais vue passer. Les octets 0 et 1 sont le point d'incertitude
/// principal, ainsi que l'unité de la vitesse.
///
/// Structure supposée de la caractéristique `6A4E3203-…` :
///
///   [compteur de page] puis N × ( id, distance_m, vitesse )
///
/// soit 3 octets par cible, jusqu'à 8 cibles. Une charge utile réduite au seul
/// octet de tête signifie « route dégagée ».
///
/// ### Protocole de vérification (10 minutes, à faire avant d'y croire)
///
/// 1. Allumer le Varia, ouvrir l'écran de spike, se connecter, regarder le
///    journal des trames brutes.
/// 2. Route vide : noter la trame au repos. Elle doit être courte et stable —
///    ça donne la taille de l'en-tête.
/// 3. Faire approcher **une seule** voiture. Un groupe de 3 octets apparaît.
///    L'octet qui décroît régulièrement est la distance ; celui qui reste
///    constant sur toute l'approche est l'identifiant.
/// 4. Comparer la distance annoncée à la réalité (un lampadaire, un panneau)
///    pour confirmer que c'est bien des mètres et non des demi-mètres.
/// 5. Pour l'unité de vitesse : approche à vitesse connue (une voiture à 50
///    km/h pendant que tu roules à 25) → l'écart est de ~7 m/s. Si l'octet
///    affiche ~7, c'est des m/s ; ~25, c'est des km/h.
///
/// Tant que ce n'est pas fait, [RadarTarget.approachSpeedRaw] garde son nom
/// délibérément neutre, et les trames brutes sont journalisées comme pour le
/// Di2 — c'est ce qui permettra de re-décoder après coup.
class VariaDecoder {
  /// Taille de l'en-tête avant la première cible. À corriger si l'étape 2 du
  /// protocole montre autre chose.
  static const headerLength = 1;

  /// Octets par cible.
  static const targetLength = 3;

  /// Le radar ne suit qu'un nombre borné de véhicules ; au-delà, on a
  /// forcément mal découpé la trame.
  static const maxTargets = 8;

  /// Décode une trame en un instantané du radar.
  ///
  /// Retourne `null` seulement si la trame est inexploitable. Une trame valide
  /// sans cible donne un [RadarSample] vide — « route dégagée » est une
  /// information, pas une absence d'information.
  RadarSample? decode(List<int> data, {DateTime? at}) {
    if (data.length < headerLength) return null;

    final body = data.length - headerLength;
    if (body % targetLength != 0) return null;

    final count = body ~/ targetLength;
    if (count > maxTargets) return null;

    final targets = <RadarTarget>[];
    for (var i = 0; i < count; i++) {
      final offset = headerLength + i * targetLength;
      final id = data[offset];
      final distance = data[offset + 1];

      // Un identifiant nul accompagné d'une distance nulle est du remplissage,
      // pas une voiture collée à la roue arrière.
      if (id == 0 && distance == 0) continue;

      targets.add(RadarTarget(
        id: id,
        distanceM: distance,
        approachSpeedRaw: data[offset + 2],
      ));
    }

    return RadarSample(at ?? DateTime.now(), List.unmodifiable(targets));
  }
}
