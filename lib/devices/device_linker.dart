import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/sensor_connection.dart';
import '../ble/sensor_hub.dart';
import 'known_device.dart';
import 'known_devices_store.dart';

/// Les capteurs qu'il reste à rattacher.
///
/// Trois filtres, dans cet ordre : connu, **connexion auto voulue**, pas déjà
/// connecté. Le deuxième est un choix du cycliste et pas une optimisation : un
/// capteur écarté à la main — vélo prêté, boîtier de l'autre vélo — ne doit
/// jamais être rattrapé au vol parce qu'un scan l'a vu passer, sinon le réglage
/// ne voudrait plus rien dire.
///
/// « En cours de connexion » compte comme manquant : c'est justement l'état où
/// l'attente s'éternise, et celui qu'on vient corriger.
List<KnownDevice> devicesToReattach(
  Iterable<KnownDevice> known,
  SensorStatus? Function(String remoteId) statusOf,
) =>
    [
      for (final device in known)
        if (device.autoConnect &&
            statusOf(device.remoteId) != SensorStatus.connected)
          device,
    ];

/// Relie un appareil au hub et le retient au catalogue.
///
/// Deux écrans font le même geste pour des raisons différentes : l'accueil
/// rattache les capteurs connus au lancement, la page des capteurs connecte
/// celui qu'on vient de taper. Le second est un tap, le premier est silencieux,
/// mais les deux doivent mémoriser exactement de la même façon — un capteur
/// appairé à la main et le même capteur retrouvé au démarrage suivant ne
/// peuvent pas donner deux entrées différentes.
///
/// Une seule instance pour toute l'appli : le balayage de rattachement ci-après
/// doit continuer pendant la sortie, donc vivre au-dessus des écrans, comme le
/// hub.
class DeviceLinker {
  DeviceLinker({required this.hub, required this.devices});

  final SensorHub hub;
  final KnownDevicesStore devices;

  /// Combien de temps on écoute, et combien de temps on se tait.
  ///
  /// Le scan actif est ce que la radio fait de plus cher : il n'a lieu que
  /// tant qu'il manque un capteur, et par fenêtres. Tout connecté, le
  /// minuteur continue de passer mais ne scanne rien — c'est ce qui permet de
  /// rattraper un capteur qui décroche en pleine sortie sans qu'on ait à
  /// relancer quoi que ce soit.
  static const _scanWindow = Duration(seconds: 8);
  static const _scanRest = Duration(seconds: 45);

  StreamSubscription<List<ScanResult>>? _sightings;
  Timer? _sweepTimer;

  /// Les rattachements en vol, par adresse. Le flux de scan republie la même
  /// liste plusieurs fois par seconde : sans ce garde-fou, un capteur vu
  /// pendant qu'on le connecte se ferait déconnecter-reconnecter en boucle.
  final _attaching = <String>{};

  bool _started = false;

  /// Met le rattachement en veille active : on écoute les trames de publicité,
  /// d'où qu'elles viennent — de notre balayage comme du scan lancé à la main
  /// depuis la page des capteurs.
  void start() {
    if (_started) return;
    _started = true;
    _sightings = FlutterBluePlus.onScanResults.listen(_onSighting);
    _scheduleSweep(after: _scanWindow + _scanRest);
  }

  /// Connecte un appareil et le retient dès qu'il a répondu.
  ///
  /// Lève si la demande de connexion échoue : c'est à l'appelant de décider si
  /// ça mérite un message — un tap raté se dit, une reconnexion silencieuse
  /// non.
  Future<SensorConnection> connect(
    BluetoothDevice device, {
    String? label,
  }) async {
    final connection = await hub.add(device, label: label);
    _rememberOnConnect(connection);
    return connection;
  }

  /// Reprend contact avec les capteurs connus, sans scan préalable.
  ///
  /// Un scan est inutile pour se rattacher à une adresse déjà connue. Les
  /// demandes partent toutes en même temps : elles rendent la main aussitôt,
  /// le système rattachant chaque capteur au fur et à mesure qu'il réapparaît.
  ///
  /// Idempotent : le hub renvoie la connexion existante si l'appareil est déjà
  /// suivi, ce qui permet de rappeler la méthode à chaque allumage du
  /// Bluetooth.
  Future<void> reconnectKnown() async {
    if (!await FlutterBluePlus.isSupported) return;

    for (final known in devices.devices) {
      if (!known.autoConnect) {
        // Dit à voix haute : une connexion auto coupée par mégarde dans le menu
        // d'un capteur ressemble en tout point à un capteur en panne, et c'est
        // la première chose à écarter quand « il ne se connecte plus ».
        debugPrint('[devices] ${known.name} : connexion auto désactivée, ignoré');
        continue;
      }
      unawaited(_reconnect(known));
    }

    // Et tout de suite le balayage : l'attente posée ci-dessus suffit pour un
    // capteur appairé au téléphone, pas pour les autres (voir [_sweep]).
    _scheduleSweep();
  }

  Future<void> _reconnect(KnownDevice known) async {
    try {
      await connect(
        BluetoothDevice.fromId(known.remoteId),
        label: known.name.isEmpty ? null : known.name,
      );
    } catch (e) {
      // Un capteur hors de portée au lancement est le cas normal, pas une
      // panne : la connexion sera retentée au prochain allumage du Bluetooth,
      // et rien à l'écran ne doit crier.
      debugPrint('[devices] ${known.name} injoignable : $e');
    }
  }

  Future<void> forget(KnownDevice known) async {
    await hub.remove(DeviceIdentifier(known.remoteId));
    await devices.forget(known.remoteId);
  }

  void _scheduleSweep({Duration after = Duration.zero}) {
    _sweepTimer?.cancel();
    _sweepTimer = Timer(after, _sweep);
  }

  /// Un tour de balayage : écouter si, et seulement si, il manque quelqu'un.
  ///
  /// Pourquoi scanner alors qu'`autoConnect` est censé rattacher tout seul :
  /// l'écoute de fond d'Android est faite de fenêtres courtes et espacées. Elle
  /// attrape sans peine un capteur qui émet en continu — le radar allumé, la
  /// ceinture portée — et rate régulièrement celui qui n'émet que par à-coups,
  /// typiquement un capteur de puissance qui se rendort dès que les manivelles
  /// s'arrêtent. Un scan actif, lui, écoute sans interruption : il tombe sur la
  /// fenêtre d'émission en une seconde ou deux.
  Future<void> _sweep() async {
    _sweepTimer?.cancel();

    final missing = devicesToReattach(devices.devices, _statusOf);
    // Bluetooth éteint : rien à tenter, et `startScan` lèverait. Le rallumage
    // repasse par `reconnectKnown`.
    final ready = FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;

    if (missing.isNotEmpty && ready && !FlutterBluePlus.isScanningNow) {
      debugPrint('[devices] balayage : ${missing.map((d) => d.name).join(', ')}');
      try {
        await FlutterBluePlus.startScan(timeout: _scanWindow);
      } catch (e) {
        debugPrint('[devices] balayage impossible : $e');
      }
    }

    // Toujours reprogrammé, même quand tout est connecté : un capteur qui
    // décroche en pleine sortie retrouve alors le chemin du retour sans que
    // personne ait à relancer l'appli.
    _scheduleSweep(after: _scanWindow + _scanRest);
  }

  SensorStatus? _statusOf(String remoteId) =>
      hub.connectionFor(DeviceIdentifier(remoteId))?.status.value;

  /// Un appareil vient d'émettre : s'il fait partie des manquants, on le prend
  /// maintenant, tant qu'il est réveillé.
  void _onSighting(List<ScanResult> results) {
    if (results.isEmpty) return;

    final wanted = {
      for (final device in devicesToReattach(devices.devices, _statusOf))
        device.remoteId: device,
    };
    if (wanted.isEmpty) return;

    for (final result in results) {
      final known = wanted[result.device.remoteId.str];
      if (known == null) continue;
      unawaited(_attach(known, result.device));
    }
  }

  Future<void> _attach(KnownDevice known, BluetoothDevice device) async {
    if (!_attaching.add(known.remoteId)) return;
    try {
      final connection = await connect(
        device,
        label: known.name.isEmpty ? null : known.name,
      );
      await connection.attachNow();
    } catch (e) {
      debugPrint('[devices] ${known.name} : rattachement échoué ($e)');
    } finally {
      _attaching.remove(known.remoteId);
    }
  }

  /// Écrit l'appareil au catalogue à chaque fois qu'il passe à *connecté*.
  ///
  /// À la connexion, pas au tap : tant que l'appareil n'a pas répondu on ne
  /// connaît ni son nom ni ses capacités, et mémoriser une adresse qui ne
  /// répond jamais encombrerait la liste. Les reconnexions repassent par là,
  /// ce qui rafraîchit la date et suffit à trier la liste par usage.
  void _rememberOnConnect(SensorConnection connection) {
    void persist() {
      if (connection.status.value != SensorStatus.connected) return;
      devices.remember(
        connection.device.remoteId.str,
        name: connection.name,
        kinds: connection.detectedKinds.value,
      );
    }

    connection.status.addListener(persist);
    // Les capacités arrivent à la découverte des services, parfois après le
    // passage à « connecté » : les deux notifications déclenchent l'écriture.
    connection.detectedKinds.addListener(persist);
    persist();
  }

  void dispose() {
    _sweepTimer?.cancel();
    _sightings?.cancel();
    _started = false;
  }
}
