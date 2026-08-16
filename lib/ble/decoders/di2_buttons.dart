/// Décodage des boutons D-Fly (satellites/sprinter) du Di2, characteristic
/// `0x2AC2` — le même service propriétaire Shimano que la position des
/// vitesses (`0x2AC1`, voir `di2.dart`), mais une characteristic à part :
/// aucun octet ne se recoupe entre les deux, pas besoin de démêler un
/// discriminant de type de trame.
///
/// Format non documenté par Shimano, établi par sniff GATT :
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
///
/// **Canaux 3 et 4 : même schéma**, offsets 3 et 4 — confirmé en réassignant
/// les deux mêmes boutons physiques sur ces canaux côté E-Tube (page Sniff
/// GATT, repères manuels), tout le reste du format identique (compteur par
/// canal, quartet haut qui classe le geste) :
///
///   20-F0-F0-11-F0   canal 3, clic simple
///   21-F0-F0-42-F0   canal 3, double-clic
///   22-F0-F0-23-F0   canal 3, maintien (début)
///   26-F0-F0-06-11   canal 4, clic simple
///   27-F0-F0-06-42   canal 4, double-clic
///   28-F0-F0-06-23   canal 4, maintien (début)
///
/// Un clic bref envoie une seule trame, rien au relâchement. **Un maintien,
/// en revanche, répète des trames tant que le bouton reste enfoncé** — et,
/// mieux, **le quartet haut du compteur classe le geste lui-même**, trouvé en
/// comparant des essais bien étiquetés (page Sniff GATT, repères manuels) :
///
///   clic simple ×3 :  24-**1**2-13-F0-F0, 25-**1**3-13-F0-F0, 26-**1**4-13-F0-F0
///   double-clic ×3 :  27-**4**5-13-F0-F0, 28-**4**6-13-F0-F0, 29-**4**7-13-F0-F0
///   maintien :        2A-**2**8-13-F0-F0 (début), 2B-**3**9-13, 2C-**3**A-13,
///                      2D-**3**B-13 (continue), 2E-**0**C-13-F0-F0 (relâché)
///
/// `0x1` clic, `0x4` double-clic (reconnu directement, sans attendre une
/// deuxième trame ni deviner un délai — un double manqué par la détection du
/// firmware, geste pas assez net, redescend simplement en `0x1`), `0x2` début
/// de maintien, `0x3` maintien qui continue, **`0x0` relâchement** — un vrai
/// signal de fin, pas une absence de trames à deviner par un délai de
/// silence. Le quartet bas continue de progresser sans se soucier des
/// frontières entre essais (`…,B,C | D,E,F,0,1,2…` dans l'exemple ci-dessus) :
/// c'est un compteur roulant ordinaire, seul le quartet haut porte le sens.
///
/// C'est [Di2ButtonPressKind.holdEnd] qui rend le relâchement d'un maintien
/// détectable en aval (`Di2ButtonGesturePolicy`, `lib/ride/`) sans délai
/// d'attente ; la cadence de répétition (~1 s, mesurée : +990 ms, +991 ms
/// entre deux trames de maintien) reste le filet de sécurité si une trame de
/// fin se perd en route.
///
/// Vu une fois pendant un essai de vitesse arrière, une trame courte
/// (`16-03`, 2 octets) que rien n'explique — [Di2ButtonChannels.update] la
/// rejette (longueur insuffisante) plutôt que de deviner à qui elle appartient.
class Di2ButtonChannels {
  // Index 0 inutilisé : le canal N vit à l'offset N, autant garder les deux
  // alignés plutôt que de décaler d'un cran partout ailleurs dans la classe.
  final _counts = List<int?>.filled(_channelCount + 1, null);

  static const _channelCount = 4;

  /// Longueur minimale pour lire le canal 1 et 2, présents sur toute
  /// installation vue jusqu'ici. Les canaux 3 et 4 sont lus s'ils sont là
  /// (`data.length` le permet), ignorés sinon — pas de raison de rejeter
  /// toute la trame pour deux canaux que personne n'a câblés.
  static const _minLength = 3;

  /// Canaux pressés dans cette trame, avec le classement lu dans leur octet —
  /// dans l'ordre où ils sont câblés (le plus petit numéro d'abord si
  /// plusieurs changent à la fois, improbable mais pas impossible sur un
  /// double clic simultané).
  ///
  /// Comparer au compteur précédent plutôt que de lire une valeur absolue est
  /// ce qui rend F0 inoffensif : pas besoin de le reconnaître comme une valeur
  /// de repos spéciale, une trame de repos ne *change* simplement rien. Vide
  /// sur une trame trop courte. Chaque canal établit sa propre référence à sa
  /// toute première apparition — pas d'événement pour elle, même compromis
  /// que [RevCounter] pour les tours de manivelle — indépendamment des
  /// autres : un canal 3 vu pour la première fois n'attend pas que 1 et 2 en
  /// soient à leur deuxième trame.
  List<({int channel, Di2ButtonPressKind? kind})> update(List<int> data) {
    if (data.length < _minLength) return const [];

    final result = <({int channel, Di2ButtonPressKind? kind})>[];
    for (var channel = 1; channel <= _channelCount; channel++) {
      if (data.length <= channel) continue;
      final value = data[channel];
      final previous = _counts[channel];
      _counts[channel] = value;
      if (previous != null && value != previous) {
        result.add((channel: channel, kind: _kindOf(value)));
      }
    }
    return result;
  }

  static Di2ButtonPressKind? _kindOf(int value) => switch (value >> 4) {
        0x1 => Di2ButtonPressKind.single,
        0x4 => Di2ButtonPressKind.doubleClick,
        0x2 => Di2ButtonPressKind.holdStart,
        0x3 => Di2ButtonPressKind.holdContinue,
        0x0 => Di2ButtonPressKind.holdEnd,
        _ => null,
      };

  void reset() => _counts.fillRange(0, _counts.length, null);
}

/// Le classement qu'une trame reçoit dans le quartet haut de son octet — voir
/// la documentation de [Di2ButtonChannels]. `null` (dans l'appelant) pour une
/// valeur qui ne correspond à aucun des cinq connus.
enum Di2ButtonPressKind { single, doubleClick, holdStart, holdContinue, holdEnd }
