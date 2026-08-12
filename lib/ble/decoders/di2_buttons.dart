/// Décodage des boutons D-Fly (satellites/sprinter) du Di2, characteristic
/// `0x2AC2` — le même service propriétaire Shimano que la position des
/// vitesses (`0x2AC1`, voir `di2.dart`), mais une characteristic à part :
/// aucun octet ne se recoupe entre les deux, pas besoin de démêler un
/// discriminant de type de trame.
///
/// Format non documenté par Shimano, établi par sniff GATT (deux canaux
/// satellite/sprinter configurés dans E-Tube) :
///
///   20-F0-11-F0-F0   canal 2 pressé (le canal 1 n'a encore jamais été
///   21-F0-12-F0-F0   canal 2 pressé  compté cette connexion : F0)
///   22-F0-13-F0-F0   canal 2 pressé
///   23-11-13-F0-F0   canal 1 pressé (son compteur quitte F0 pour de bon)
///   24-12-13-F0-F0   canal 1 pressé
///   25-13-13-F0-F0   canal 1 pressé
///           ^  ^
///           |  +-- offset 2 : compteur du canal 2
///           +----- offset 1 : compteur du canal 1
///
/// offset 0 : compteur global de trames, tous canaux confondus — inutile ici,
/// une seule caractéristique n'a personne d'autre à départager, contrairement
/// au Control Point de puissance partagé entre plusieurs procédures.
/// Offsets 3-4 toujours F0-F0 dans nos relevés (deux canaux configurés
/// seulement sur trois ou quatre possibles côté E-Tube) : vraisemblablement
/// les canaux 3 et 4, à confirmer le jour où quelqu'un les câble.
///
/// Une seule trame par clic, aucune au relâchement (confirmé sur le
/// terrain) : chaque canal ne peut donc que « presser », jamais « tenir ».
///
/// Vu une fois pendant un essai de vitesse arrière, une trame courte
/// (`16-03`, 2 octets) que rien n'explique — [Di2ButtonChannels.update] la
/// rejette (longueur insuffisante) plutôt que de deviner à qui elle appartient.
class Di2ButtonChannels {
  int? _channel1Count;
  int? _channel2Count;

  static const _channel1Offset = 1;
  static const _channel2Offset = 2;
  static const _minLength = 3;

  /// Canaux pressés dans cette trame, dans l'ordre où ils sont câblés (1 puis
  /// 2 si les deux changent à la fois — improbable mais pas impossible sur un
  /// double clic simultané).
  ///
  /// Comparer au compteur précédent plutôt que de lire une valeur absolue est
  /// ce qui rend F0 inoffensif : pas besoin de le reconnaître comme une valeur
  /// de repos spéciale, une trame de repos ne *change* simplement rien. Vide
  /// sur une trame trop courte, sur la toute première reçue après une
  /// connexion — elle sert de référence, pas d'événement, même compromis que
  /// [RevCounter] pour les tours de manivelle — et sur une notification
  /// répétée sans changement.
  List<int> update(List<int> data) {
    if (data.length < _minLength) return const [];

    final channel1 = data[_channel1Offset];
    final channel2 = data[_channel2Offset];
    final prevChannel1 = _channel1Count;
    final prevChannel2 = _channel2Count;
    _channel1Count = channel1;
    _channel2Count = channel2;

    if (prevChannel1 == null || prevChannel2 == null) return const [];

    return [
      if (channel1 != prevChannel1) 1,
      if (channel2 != prevChannel2) 2,
    ];
  }

  void reset() {
    _channel1Count = null;
    _channel2Count = null;
  }
}
