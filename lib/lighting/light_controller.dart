import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/sensor_uuids.dart';
import 'auto_lighting.dart';

/// Traduit une intention en commande envoyée à une lampe.
///
/// Séparé de [AutoLightingPolicy] à dessein : la décision est du calcul pur et
/// testable, l'actionnement dépend d'un protocole propriétaire. Le jour où tu
/// changes de lampe, seule cette couche bouge.
abstract class RearLightController {
  Future<void> apply(RearLightMode mode);
}

/// ⚠️ **Aucun contrôleur possible : le phare actuel n'a pas de radio.**
///
/// Le phare est un Ravemen FR300, et c'est la version **sans ANT+** — vérifié
/// deux fois : l'appairage au CC600 échoue, et aucune entrée `bike_light_*`
/// autre que le Varia n'apparaît dans les `.fit` du compteur. Il n'y a donc
/// rien à piloter, ni en BLE, ni en ANT+, ni depuis un compteur.
///
/// Ne pas repartir chercher un service qui n'existe pas. L'interface reste là
/// parce qu'elle aura du sens avec un futur phare ; en attendant, la politique
/// avant est **consultative**, et c'est un usage à part entière : le FR300 se
/// commute à la main, donc l'app sert à *rappeler* de le faire au crépuscule
/// plutôt qu'à le faire elle-même. Câbler [LoggingLightController] dessus, et
/// brancher une notification quand [FrontLightMode] change.
///
/// À noter : le FR300 a son propre capteur de luminosité et un mode auto
/// on/off. L'essentiel de l'automatisme avant est déjà dans la lampe.
abstract class FrontLightController {
  Future<void> apply(FrontLightMode mode);
}

/// Applique une décision aux lampes présentes.
///
/// N'envoie une commande **que sur changement effectif** : une lampe n'a pas
/// besoin qu'on lui répète son mode à chaque tick, et chaque écriture BLE coûte
/// de la batterie des deux côtés.
class LightingActuator {
  LightingActuator({this.front, this.rear});

  final FrontLightController? front;
  final RearLightController? rear;

  FrontLightMode? _lastFront;
  RearLightMode? _lastRear;

  Future<void> apply(LightingDecision decision) async {
    final f = decision.front;
    if (f != null && f != _lastFront) {
      _lastFront = f;
      await front?.apply(f);
    }

    final r = decision.rear;
    if (r != null && r != _lastRear) {
      _lastRear = r;
      await rear?.apply(r);
    }
  }
}

/// Journalise ce qui serait envoyé, sans rien envoyer.
///
/// C'est l'implémentation active tant que l'encodage des commandes n'est pas
/// décodé : la politique tourne en vrai pendant une sortie, tu lis dans les
/// logs ce qu'elle aurait commandé, et tu la valides **avant** de brancher
/// l'actionneur.
class LoggingLightController
    implements FrontLightController, RearLightController {
  LoggingLightController(this.label);

  final String label;

  @override
  Future<void> apply(Object mode) async {
    debugPrint('[light:$label] ${(mode as Enum).name}');
  }
}

/// Commande le feu arrière d'un Garmin Varia.
///
/// ⚠️ **Non fonctionnel : l'encodage des commandes est inconnu.**
///
/// Mais un chemin de contrôle existe bel et bien, et c'est prouvé : dans les
/// `.fit` du CC600, le Varia s'inscrit **deux fois** sous le même numéro ANT+
/// (55794), une fois comme `bike_radar` (type 40) et une fois comme
/// `bike_light_main` (type 35). Ce second profil est celui des lampes
/// pilotables du Light Network ANT+ — la lampe est donc conçue pour recevoir
/// des commandes. La caractéristique `6A4E3201-…` est très probablement le même
/// canal côté BLE. Ça vaut le sniff.
///
/// Le service radar expose une seconde caractéristique (`6A4E3201-…`) qui est
/// le candidat évident, mais je n'ai vu passer aucune commande et je ne vais
/// pas inventer des octets — on a déjà vu où ça mène avec le Di2.
///
/// ### Comment obtenir l'encodage
///
/// Même méthode que pour E-TUBE, et elle a marché :
///
/// 1. Android : options développeur → « Journal de trace Bluetooth HCI ».
/// 2. Ouvrir **Garmin Connect** (ou un Edge appairé en BLE), changer le mode du
///    feu à la main, plusieurs fois, en notant l'ordre des modes.
/// 3. `adb bugreport`, extraire `btsnoop_hci.log`, ouvrir dans Wireshark,
///    filtrer sur `btatt`.
/// 4. Repérer les écritures sur `6A4E3201-…` : une trame courte et différente
///    par mode. Noter aussi toute séquence d'initialisation qui précéderait —
///    la lampe peut exiger une poignée de main avant d'accepter des commandes.
///
/// Reporte ensuite les octets dans [_commandFor] et retire le garde-fou.
class VariaRearLightController implements RearLightController {
  VariaRearLightController(this.device);

  final BluetoothDevice device;

  BluetoothCharacteristic? _control;

  Future<void> bind() async {
    final services = await device.discoverServices();
    for (final service in services) {
      for (final c in service.characteristics) {
        if (c.uuid == BleCharacteristics.variaControl) {
          _control = c;
          debugPrint('[light:arrière] contrôle trouvé : ${c.uuid}');
          return;
        }
      }
    }
    debugPrint('[light:arrière] aucune caractéristique de contrôle');
  }

  /// Octets à écrire pour un mode donné. `null` tant que non décodé.
  List<int>? _commandFor(RearLightMode mode) => null;

  @override
  Future<void> apply(RearLightMode mode) async {
    final control = _control;
    final command = _commandFor(mode);

    if (control == null || command == null) {
      debugPrint('[light:arrière] ${mode.name} : commande inconnue, rien envoyé');
      return;
    }

    try {
      await control.write(command, withoutResponse: false);
    } catch (e) {
      // Une lampe qui refuse une commande ne doit pas interrompre la sortie.
      debugPrint('[light:arrière] écriture refusée : $e');
    }
  }
}
