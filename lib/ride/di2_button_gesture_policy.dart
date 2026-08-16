import '../ble/decoders/di2_buttons.dart' show Di2ButtonPressKind;
import '../ble/samples.dart';

/// Ce qu'une pression sur un canal du D-Fly (Di2) finit par être, une fois
/// qu'on a laissé passer assez de temps pour trancher.
enum Di2ButtonGesture { click, doubleClick, longPress }

/// Un geste résolu, sur un canal donné.
class Di2ButtonGestureEvent {
  const Di2ButtonGestureEvent(this.channel, this.gesture);

  final Di2ButtonChannel channel;
  final Di2ButtonGesture gesture;
}

/// Classifie les pressions brutes du D-Fly en clic simple, double-clic ou
/// appui long — pure et pilotée par une horloge passée en paramètre, comme
/// [AutoReturnPolicy]/[RadarWakePolicy] (`lib/ride/`).
///
/// **Le double-clic se lit directement dans la trame**, pas par une fenêtre
/// de temps entre deux pressions : le D-Fly le détecte lui-même et le classe
/// dans le quartet haut du compteur (`Di2ButtonPressKind.doubleClick`, voir
/// `ble/decoders/di2_buttons.dart`), confirmé sur plusieurs dizaines
/// d'essais bien étiquetés. Une première version tentait de le reconnaître à
/// l'écart entre deux trames (fenêtre de quelques centaines de ms) : sur le
/// terrain, deux pressions distinctes sur ce bouton n'arrivent jamais en
/// dessous d'1,4 s d'écart — bien plus lent qu'un double-clic de souris — ce
/// qui rendait cette approche à la fois trop lente et peu fiable.
///
/// **L'appui long se lit lui aussi directement dans la trame, sans cumuler
/// 2 s en plus** : `Di2ButtonPressKind.holdStart` ne paraît que lorsque le
/// D-Fly a lui-même déjà tranché que la pression en cours n'est pas un clic —
/// attendre encore [longPressHold] par-dessus ce délai interne (le firmware
/// ne classe rien avant environ une seconde de maintien) ne faisait que
/// doubler l'attente pour rien. [onPress] déclenche donc l'appui long **dès**
/// `holdStart`, sans savoir combien de temps le maintien durera au final.
///
/// **Le relâchement se lit directement dans la trame aussi** :
/// `Di2ButtonPressKind.holdEnd`, le même quartet qui vaut `holdContinue` sur
/// les trames du maintien après son début. Pas besoin d'un délai de silence
/// pour conclure au relâchement. [resolve] reste un filet de sécurité, pour
/// une trame de fin qui se perdrait en route (le D-Fly répète sinon ses
/// trames de maintien à peu près une fois par seconde, mesuré sur le
/// terrain : +990 ms, +991 ms entre deux trames).
///
/// **Le clic simple se résout donc lui aussi instantanément**, sans délai
/// d'attente : le D-Fly ne classe jamais une pression `single` au début d'un
/// maintien, qui commence toujours par `holdStart` — vérifié sur le terrain.
/// Une trame `single` ne peut donc pas encore devenir un maintien, il n'y a
/// rien à attendre.
///
/// [longPressHold] et [resolutionDelay] ne servent donc plus qu'en secours,
/// pour une trame sans classement reconnu (`kind == null`, jamais observé en
/// pratique mais pas exclu) : elle attend alors [resolve], au cas où elle
/// serait malgré tout le début d'un maintien.
class Di2ButtonGesturePolicy {
  Di2ButtonGesturePolicy({
    this.holdRepeatGapMax = const Duration(milliseconds: 1400),
    this.resolutionDelay = const Duration(milliseconds: 1000),
    this.longPressHold = const Duration(seconds: 2),
  });

  /// Au-delà de ce délai sans nouvelle trame sur le canal, le maintien est
  /// considéré relâché. Au-dessus de la cadence mesurée (~990 ms), marge de
  /// jitter comprise.
  final Duration holdRepeatGapMax;

  /// Délai minimal avant de résoudre un clic simple, même si le canal est
  /// déjà silencieux — le temps de laisser sa chance à un maintien qui
  /// commencerait à peine.
  final Duration resolutionDelay;

  /// Cumul depuis la première pression à partir duquel une trame sans
  /// classement reconnu devient un appui long — repli rarement emprunté,
  /// `holdStart` réglant en pratique la question bien avant ce seuil.
  final Duration longPressHold;

  final _pending = <Di2ButtonChannel, _PendingPress>{};

  /// Une pression brute reçue du décodeur, avec le classement que le D-Fly en
  /// a fait ([Di2ButtonPressKind], `null` pour une valeur non reconnue).
  /// Résout **immédiatement** le double-clic, l'appui long (`holdStart`) et
  /// le clic — qu'il soit isolé (`single`) ou conclu par un relâchement de
  /// maintien encore court (`holdEnd`) — tous lus dans la trame elle-même.
  /// Seule une trame sans classement reconnu attend encore [resolve].
  Di2ButtonGesture? onPress(
    Di2ButtonChannel channel,
    DateTime at,
    Di2ButtonPressKind? kind,
  ) {
    if (kind == Di2ButtonPressKind.doubleClick) {
      _pending.remove(channel);
      return Di2ButtonGesture.doubleClick;
    }

    if (kind == Di2ButtonPressKind.holdStart) {
      // Le D-Fly ne classe une trame « début de maintien » qu'une fois
      // lui-même convaincu qu'il ne s'agit pas d'un clic — attendre encore
      // [longPressHold] par-dessus son propre délai de reconnaissance
      // doublerait l'attente pour rien. On lui fait confiance directement :
      // appui long dès cette trame, `longPressFired` posé tout de suite pour
      // que les `holdContinue` et le `holdEnd` qui suivent s'absorbent sans
      // rien redéclencher (voir plus bas et [Di2ButtonPressKind.holdEnd]).
      _pending[channel] = _PendingPress(firstAt: at, lastAt: at)
        ..longPressFired = true;
      return Di2ButtonGesture.longPress;
    }

    if (kind == Di2ButtonPressKind.single) {
      // Le D-Fly ne classe jamais une pression « simple » au début d'un
      // maintien — celui-ci commence toujours par `holdStart` (vérifié sur
      // le terrain), jamais par `single`. Cette trame ne peut donc pas
      // devenir autre chose : rien à attendre, contrairement au clic sans
      // classement (voir plus bas) qui doit encore laisser sa chance à un
      // maintien qui commencerait à peine.
      _pending.remove(channel);
      return Di2ButtonGesture.click;
    }

    if (kind == Di2ButtonPressKind.holdEnd) {
      // Relâchement confirmé par le D-Fly lui-même. `pending.longPressFired`
      // est déjà vrai dans l'immense majorité des cas — posé dès `holdStart`,
      // ci-dessus — donc rien de plus à faire ici : ce n'est qu'un repli pour
      // la séquence qui aurait démarré sans `holdStart` connu (`kind == null`
      // en tête, jamais observé en pratique) et n'a pas eu le temps
      // d'atteindre [longPressHold], où la trame de fin vaut alors un clic.
      final pending = _pending.remove(channel);
      if (pending == null || pending.longPressFired) return null;
      return Di2ButtonGesture.click;
    }

    final pending = _pending[channel];
    if (pending == null) {
      _pending[channel] = _PendingPress(firstAt: at, lastAt: at);
      return null;
    }

    // La queue d'un maintien déjà rendu en appui long, avant que sa trame de
    // relâchement (`holdEnd`, ci-dessus) n'arrive : on absorbe sans rien
    // redéclencher plutôt que de repartir d'une séquence neuve — observé sur
    // le terrain avant l'ajout de la branche `holdEnd`.
    if (pending.longPressFired) {
      pending.lastAt = at;
      return null;
    }

    pending.lastAt = at;
    if (at.difference(pending.firstAt) >= longPressHold) {
      pending.longPressFired = true;
      return Di2ButtonGesture.longPress;
    }
    return null;
  }

  /// Résolutions qui ne dépendent que du temps qui passe, sans nouvelle
  /// trame — appelée depuis un tic dédié, plus rapide que celui de la
  /// coquille (`RideShellPage._buttonTick`, 200 ms). **Filet de sécurité
  /// seulement** : clic, double-clic et appui long se résolvent tous
  /// instantanément dans [onPress] en pratique (classement lu dans la trame).
  /// Cette méthode ne sert donc qu'à deux cas rares — une trame sans
  /// classement reconnu (`kind == null`) qui doit malgré tout finir par se
  /// résoudre en clic une fois le canal silencieux, et une trame de fin de
  /// maintien (`holdEnd`) perdue en route, rattrapée ici par le silence
  /// plutôt que jamais résolue.
  ///
  /// **Le silence est vérifié en premier, jamais l'appui long en premier** :
  /// un clic isolé qui n'a jamais répété peut voir passer les tics qui
  /// auraient dû le résoudre en clic simple avant que le cumul depuis la
  /// première pression n'atteigne [longPressHold] — sans ce garde-fou, un
  /// simple clic mal tombé se ferait passer pour un appui long.
  List<Di2ButtonGestureEvent> resolve(DateTime now) {
    final resolved = <Di2ButtonGestureEvent>[];
    _pending.removeWhere((channel, pending) {
      final sinceLast = now.difference(pending.lastAt);

      if (sinceLast > holdRepeatGapMax) {
        // Silence confirmé : l'appui long déjà rendu n'a plus rien à ajouter
        // pour sa queue — voir le même garde-fou dans [onPress].
        if (pending.longPressFired) return true;
        final sinceFirst = now.difference(pending.firstAt);
        if (sinceFirst < resolutionDelay) return false;
        resolved.add(Di2ButtonGestureEvent(channel, Di2ButtonGesture.click));
        return true;
      }

      // Toujours actif (trame récente) : l'appui long ne se déclenche que
      // tant que le canal continue de se manifester, et une fois rendu on
      // reste en attente du relâchement plutôt que d'être retiré tout de
      // suite — sinon la prochaine trame de la même poignée redémarre une
      // séquence neuve.
      if (!pending.longPressFired && now.difference(pending.firstAt) >= longPressHold) {
        resolved.add(Di2ButtonGestureEvent(channel, Di2ButtonGesture.longPress));
        pending.longPressFired = true;
      }
      return false;
    });
    return resolved;
  }

  void reset() => _pending.clear();
}

class _PendingPress {
  _PendingPress({required this.firstAt, required this.lastAt});

  final DateTime firstAt;
  DateTime lastAt;
  bool longPressFired = false;
}
