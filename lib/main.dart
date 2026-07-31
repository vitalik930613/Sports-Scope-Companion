import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'account/account_page.dart';
import 'account/rider_profile_store.dart';
import 'account/site_session.dart';
import 'account/threshold_gap.dart';
import 'ble/samples.dart';
import 'ble/sensor_connection.dart';
import 'ble/sensor_hub.dart';
import 'ble/sensor_profile.dart';
import 'devices/known_device.dart';
import 'devices/known_devices_store.dart';
import 'drivetrain.dart';
import 'navigation/navigation_picker_sheet.dart';
import 'navigation/navigation_target.dart';
import 'navigation/route_catalog_store.dart';
import 'ride/radar_debug_page.dart';
import 'ride/ride_shell_page.dart';
import 'recording/gps_source.dart';
import 'recording/recording_card.dart';
import 'recording/ride_recorder.dart';
import 'recording/ride_store.dart';
import 'recording/rides_page.dart';
import 'ui/metric_tile.dart';
import 'ui/radar_card.dart';
import 'ui/sensor_icons.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Le catalogue est lu avant le premier écran : la liste des capteurs connus
  // doit être là dès l'affichage, sinon elle apparaîtrait après coup.
  final devices = await KnownDevicesStore.open();
  // Le magasin de sorties, lui, n'est qu'un chemin sur le disque : l'ouvrir ici
  // évite un `Future` de plus dans l'arbre de widgets.
  final rides = await RideStore.open();
  // L'état de session est lu avant le premier écran pour la même raison : le
  // bandeau « non connecté » doit être juste dès l'affichage, pas apparaître
  // après coup.
  final session = await SiteSession.open();
  // Les seuils du cycliste sont relus au démarrage : ils viennent du site, donc
  // une sortie lancée hors réseau n'aurait sinon aucune zone à afficher.
  final riderProfile = await RiderProfileStore.open();
  // Et les itinéraires du compte, pour la même raison encore : on choisit son
  // tracé au départ, c'est-à-dire à l'endroit de la sortie où le réseau manque
  // le plus souvent.
  final routes = await RouteCatalogStore.open();
  runApp(SportsScopeApp(
    devices: devices,
    rides: rides,
    session: session,
    riderProfile: riderProfile,
    routes: routes,
  ));
}

class SportsScopeApp extends StatefulWidget {
  const SportsScopeApp({
    super.key,
    required this.devices,
    required this.rides,
    required this.session,
    required this.riderProfile,
    required this.routes,
  });

  final KnownDevicesStore devices;
  final RideStore rides;
  final RouteCatalogStore routes;
  final SiteSession session;
  final RiderProfileStore riderProfile;

  @override
  State<SportsScopeApp> createState() => _SportsScopeAppState();
}

class _SportsScopeAppState extends State<SportsScopeApp> {
  /// Le hub vit au-dessus des écrans : les capteurs restent connectés quand on
  /// passe de la page de diagnostic à la navigation, et un lien entrant peut
  /// ouvrir la navigation sans repasser par la page des capteurs.
  final _hub = SensorHub();

  /// L'enregistreur vit au même étage que le hub, et pour la même raison : une
  /// sortie commencée sur l'écran des capteurs doit continuer pendant toute la
  /// navigation, et survivre au retour en arrière.
  late final _recorder = RideRecorder(hub: _hub, store: widget.rides);

  final _navigatorKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _listenForLinks();
  }

  /// « Ouvrir dans l'appli » depuis le site, ou un lien d'itinéraire partagé.
  ///
  /// Le flux suffit : `uriLinkStream` émet le lien initial puis les suivants (cf. le
  /// README d'app_links). Y ajouter un `getInitialLink()` ouvrait la navigation DEUX
  /// fois au démarrage à froid — sans conséquence tant que les deux pages étaient
  /// identiques, fatal depuis que le lien porte un jeton de session à usage unique :
  /// la première ouverture le consommait, la seconde le trouvait déjà utilisé et
  /// retombait en anonyme… par-dessus la première, connectée. C'est cette page-là
  /// qu'on voyait.
  void _listenForLinks() {
    _linkSub = _appLinks.uriLinkStream.listen(_openLink);
  }

  Future<void> _openLink(Uri uri) async {
    final target = NavigationTarget.parse(uri);
    if (target == null) {
      debugPrint('[links] lien ignoré : $uri');
      return;
    }
    await openNavigation(
      _navigatorKey.currentContext,
      target: target,
      hub: _hub,
      recorder: _recorder,
      session: widget.session,
      riderProfile: widget.riderProfile,
      routes: widget.routes,
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _recorder.dispose();
    _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Scope',
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: SensorsPage(
        devices: widget.devices,
        hub: _hub,
        recorder: _recorder,
        rides: widget.rides,
        session: widget.session,
        riderProfile: widget.riderProfile,
        routes: widget.routes,
      ),
    );
  }
}

/// Ouvre la navigation, après avoir obtenu la position.
///
/// La permission est demandée ici et pas dans la page : le WebView ne sait pas
/// la réclamer lui-même, il se contente de relayer une autorisation que
/// l'application doit déjà détenir. Sans elle, la carte s'afficherait sans
/// jamais suivre le cycliste — une panne silencieuse.
Future<void> openNavigation(
  BuildContext? context, {
  required NavigationTarget target,
  required SensorHub hub,
  required RideRecorder recorder,
  required SiteSession session,
  required RiderProfileStore riderProfile,
  required RouteCatalogStore routes,
}) async {
  if (context == null || !context.mounted) return;

  final status = await Permission.location.request();
  if (!context.mounted) return;

  if (!status.isGranted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sans autorisation de position, la navigation ne peut pas '
          'te suivre.'),
    ));
    return;
  }

  if (!recorder.isActive) {
    await _offerRecording(context, recorder);
    if (!context.mounted) return;
  }

  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => RideShellPage(
      target: target,
      hub: hub,
      recorder: recorder,
      session: session,
      riderProfile: riderProfile,
      routes: routes,
    ),
  ));
}

/// Propose de lancer l'enregistrement, juste avant de partir.
///
/// C'est le bon moment pour le demander — le cycliste a encore ses mains, et
/// une sortie enregistrée depuis le début vaut mieux qu'une sortie rattrapée en
/// route. Ce n'est plus la *seule* occasion pour autant : la page Effort porte
/// un bouton de départ tant que rien n'est enregistré, parce que c'est là qu'on
/// s'aperçoit d'avoir dit non.
///
/// Le démarrage n'est pas automatique : ouvrir la carte pour vérifier une route
/// avant de partir fabriquerait une sortie de deux minutes à chaque fois, et
/// c'est le genre de déchet qu'on finit par ne plus trier.
///
/// **La navigation s'ouvre dans tous les cas.** Refus, panne de GPS, position
/// désactivée : l'enregistrement est un supplément, la navigation est le but.
Future<void> _offerRecording(
  BuildContext context,
  RideRecorder recorder,
) async {
  final wanted = await showDialog<bool>(
    context: context,
    // Pas de sortie par le côté : la question mérite une réponse, et un tap à
    // côté ne doit pas trancher à la place du cycliste.
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Enregistrer cette sortie ?'),
      content: const Text(
        'La trace, les capteurs et le dénivelé seront écrits pendant toute la '
        'navigation.\n\nSi tu dis non, la page Effort gardera un bouton pour '
        'démarrer en route — mais ce qui précède ne sera pas rattrapé.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Naviguer seulement'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );

  if (wanted != true || !context.mounted) return;

  try {
    await recorder.start();
  } on GpsUnavailable catch (e) {
    if (!context.mounted) return;
    await _tellRecordingFailed(context, e.message);
  } catch (e) {
    if (!context.mounted) return;
    await _tellRecordingFailed(context, 'Enregistrement impossible : $e');
  }
}

/// Dit qu'on partira sans trace.
///
/// Une dialogue et pas un `SnackBar` : la navigation s'ouvre dans la seconde et
/// recouvrirait le message avant qu'il ait été lu. Le cycliste doit savoir en
/// partant que rien ne sera enregistré — il le découvrirait sinon en rentrant.
Future<void> _tellRecordingFailed(BuildContext context, String message) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sortie non enregistrée'),
      content: Text('$message\n\nLa navigation s\'ouvre quand même.'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Continuer'),
        ),
      ],
    ),
  );
}

/// Écran de diagnostic des capteurs : scanner, connecter, afficher en direct.
///
/// Ce n'est pas l'écran de sortie — la navigation, elle, est dans
/// [RideShellPage]. Celui-ci reste l'outil de dépannage : voir qui répond, ce
/// qu'on décode, et les trames brutes pour finir de décoder les octets Di2
/// encore inconnus (offset 3, offset 15).
class SensorsPage extends StatefulWidget {
  const SensorsPage({
    super.key,
    required this.devices,
    required this.hub,
    required this.recorder,
    required this.rides,
    required this.session,
    required this.riderProfile,
    required this.routes,
  });

  final KnownDevicesStore devices;

  /// Les itinéraires du compte, pour le sélecteur de navigation.
  final RouteCatalogStore routes;

  /// Le hub appartient à l'application, pas à cet écran : les capteurs doivent
  /// rester connectés quand on passe en navigation.
  final SensorHub hub;

  /// L'enregistreur, pour la même raison que le hub.
  final RideRecorder recorder;

  final RideStore rides;

  /// La session du site, partagée avec la navigation : elle appartient à
  /// l'application, pas à cet écran.
  final SiteSession session;

  /// Les seuils du cycliste, transmis à la navigation qui les tient à jour
  /// depuis le site. Cet écran ne les affiche pas, il signale seulement ce qui
  /// leur manque pour que les zones du bandeau de sortie existent.
  final RiderProfileStore riderProfile;

  @override
  State<SensorsPage> createState() => _SensorsPageState();
}

class _SensorsPageState extends State<SensorsPage> {
  final _drivetrain = Drivetrain.road;
  final _recentFrames = <RawFrame>[];

  List<ScanResult> _results = const [];
  bool _scanning = false;
  var _adapterState = BluetoothAdapterState.unknown;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanStateSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<RawFrame>? _frameSub;

  KnownDevicesStore get _devices => widget.devices;
  SensorHub get _hub => widget.hub;
  RideRecorder get _recorder => widget.recorder;

  void _openRides() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RidesPage(store: widget.rides, recorder: _recorder),
    ));
  }

  /// Le banc d'essai du radar. Sa place est ici et pas dans un écran caché : le
  /// jour où le décodage du Varia sera confirmé, c'est de cette page qu'on
  /// partira pour comparer ce qu'affiche une vraie voiture à ce qu'affiche une
  /// voiture simulée.
  void _openRadarSimulator() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const RadarDebugPage(),
    ));
  }

  void _openAccount() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AccountPage(session: widget.session),
    ));
  }

  @override
  void initState() {
    super.initState();

    _devices.addListener(_onDevicesChanged);
    // La navigation, elle aussi, constate l'état de la session : revenir d'une
    // sortie doit rafraîchir le bandeau ici.
    widget.session.addListener(_onSessionChanged);

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (mounted) setState(() => _results = results);
    });
    _scanStateSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _scanning = scanning);
    });

    // La reconnexion est déclenchée par l'état de l'adaptateur, pas par
    // `initState` : au lancement, `adapterStateNow` vaut encore `unknown` — il
    // n'est renseigné qu'une fois le flux écouté. Tester l'état ici ne
    // reconnectait donc jamais rien.
    //
    // Passer par le flux couvre aussi le Bluetooth allumé après coup, cas
    // banal : on ouvre l'appli, puis on active le Bluetooth.
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() => _adapterState = state);
      if (state == BluetoothAdapterState.on) _reconnectKnownDevices();
    });

    // Les dernières trames brutes restent à l'écran : c'est l'outil de reverse,
    // et ça montre immédiatement si un capteur n'émet que du silence.
    _frameSub = _hub.rawFrames.listen((frame) {
      if (!mounted) return;
      setState(() {
        _recentFrames.insert(0, frame);
        if (_recentFrames.length > 12) _recentFrames.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _devices.removeListener(_onDevicesChanged);
    widget.session.removeListener(_onSessionChanged);
    _scanSub?.cancel();
    _scanStateSub?.cancel();
    _adapterSub?.cancel();
    _frameSub?.cancel();
    // Le hub n'est pas fermé ici : il survit à cet écran.
    super.dispose();
  }

  void _onDevicesChanged() {
    if (mounted) setState(() {});
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
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
  Future<void> _reconnectKnownDevices() async {
    if (!await FlutterBluePlus.isSupported) return;

    for (final known in _devices.devices) {
      if (!known.autoConnect) continue;
      unawaited(_connect(
        BluetoothDevice.fromId(known.remoteId),
        label: known.name.isEmpty ? null : known.name,
        announce: false,
      ));
    }
  }

  Future<void> _startScan() async {
    if (!await FlutterBluePlus.isSupported) {
      _toast('Bluetooth non supporté sur cet appareil');
      return;
    }
    if (_adapterState != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        _toast('Active le Bluetooth pour scanner');
        return;
      }
    }

    setState(() => _results = const []);
    // Scan large, sans filtre de service : le Di2 n'annonce pas forcément son
    // service propriétaire dans ses trames de publicité.
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  /// Connecte un appareil et le retient dès qu'il a répondu.
  ///
  /// [announce] distingue le geste explicite (tap sur un résultat de scan, où
  /// un échec mérite un message) de la reconnexion silencieuse au démarrage.
  Future<void> _connect(
    BluetoothDevice device, {
    String? label,
    bool announce = true,
  }) async {
    if (announce) await FlutterBluePlus.stopScan();

    try {
      final connection = await _hub.add(device, label: label);
      _rememberOnConnect(connection);
      if (mounted) setState(() {});
    } catch (e) {
      if (announce) _toast('Connexion échouée : $e');
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
      _devices.remember(
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

  Future<void> _forget(KnownDevice known) async {
    await _hub.remove(DeviceIdentifier(known.remoteId));
    await _devices.forget(known.remoteId);
    if (mounted) setState(() {});
  }

  /// Choix de ce qu'on navigue.
  ///
  /// Le chemin normal reste le lien depuis le site (« Ouvrir dans l'appli »),
  /// qui arrive en lien entrant et court-circuite tout ceci. Ce panneau est là
  /// pour le reste : reprendre un de ses itinéraires, partir sans tracé, ou
  /// ouvrir un lien reçu ailleurs.
  ///
  /// La feuille ne fait que **rendre une cible** — ouvrir la navigation demande
  /// une permission et pose la question de l'enregistrement, deux choses qui
  /// n'ont rien à faire dans un sélecteur.
  Future<void> _chooseNavigation() async {
    final target = await showModalBottomSheet<NavigationTarget>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NavigationPickerSheet(catalog: widget.routes),
    );

    if (target == null || !mounted) return;

    await openNavigation(
      context,
      target: target,
      hub: _hub,
      recorder: widget.recorder,
      session: widget.session,
      riderProfile: widget.riderProfile,
      routes: widget.routes,
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final known = _devices.devices;
    // Un capteur déjà connu n'a rien à faire dans les résultats de scan : il
    // est déjà listé au-dessus, avec son état réel.
    final knownIds = {for (final device in known) device.remoteId};
    final discovered = [
      for (final result in _results)
        if (!knownIds.contains(result.device.remoteId.str)) result,
    ];

    // Un appareil qu'on vient de taper n'est pas encore au catalogue — il n'y
    // entre qu'une fois connecté. Sans cette section, la connexion en cours
    // n'aurait aucun retour visuel.
    final pending = [
      for (final connection in _hub.connections)
        if (!knownIds.contains(connection.device.remoteId.str)) connection,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capteurs'),
        actions: [
          IconButton(
            onPressed: _openAccount,
            // La couleur porte l'information : l'icône ne change pas, seul son
            // état le fait — vert connecté, orange anonyme, gris inconnu.
            icon: Icon(
              Icons.account_circle,
              color: switch (widget.session.signedIn) {
                true => Colors.teal,
                false => Colors.orange,
                null => null,
              },
            ),
            tooltip: 'Compte',
          ),
          IconButton(
            onPressed: _openRides,
            icon: const Icon(Icons.route),
            tooltip: 'Mes sorties',
          ),
          IconButton(
            onPressed: _openRadarSimulator,
            icon: const Icon(Icons.radar),
            tooltip: 'Simuler le radar',
          ),
          IconButton(
            onPressed: _scanning ? FlutterBluePlus.stopScan : _startScan,
            icon: Icon(_scanning ? Icons.stop : Icons.search),
            tooltip: _scanning ? 'Arrêter' : 'Scanner',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _chooseNavigation,
        icon: const Icon(Icons.navigation),
        label: const Text('Naviguer'),
      ),
      body: ListView(
        // Une `ListView` sans marge explicite prendrait celle du système toute
        // seule ; en lui en donnant une, on hérite du devoir de la compléter —
        // sinon la dernière carte de la liste finit sous la barre de
        // navigation. Le bouton flottant s'ajoute par-dessus, d'où le supplément
        // qui permet de faire défiler ce qu'il recouvre.
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + 72 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          // Bluetooth éteint, capteurs muets : autant le dire, sinon la page
          // ressemble à une panne de l'appli.
          if (_adapterState == BluetoothAdapterState.off)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.bluetooth_disabled),
                title: const Text('Bluetooth éteint'),
                subtitle: const Text(
                    'Les capteurs se rattacheront seuls une fois activé.'),
                trailing: TextButton(
                  onPressed: () => FlutterBluePlus.turnOn(),
                  child: const Text('Activer'),
                ),
              ),
            ),
          // Une navigation anonyme n'a l'air de rien : la carte s'affiche, mais
          // sans les itinéraires du compte, avec le fond de carte par défaut et
          // des POI muets. Autant le dire au départ plutôt que de le découvrir
          // sur la route.
          if (widget.session.signedIn == false)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.person_off),
                title: const Text('Non connecté au site'),
                subtitle: const Text('Sans session : pas d\'itinéraires '
                    'sauvegardés, fond de carte par défaut, POI indisponibles.'),
                trailing: TextButton(
                  onPressed: _openAccount,
                  child: const Text('Se connecter'),
                ),
              ),
            ),
          // Sans seuils, le bandeau de sortie n'affiche qu'un tiret à la place
          // des zones, et rien sur la route ne dit d'où vient le trou. Le seul
          // moment où l'on peut encore le combler, c'est ici — le geste se fait
          // sur le site, pas au guidon.
          //
          // Pas affiché en session anonyme : le bandeau juste au-dessus dit
          // déjà que rien n'est connecté, ce qui est la vraie cause. Deux cartes
          // pour un seul problème se lisent comme deux problèmes.
          if (widget.session.signedIn != false) _thresholdGapCard(),
          // L'enregistrement passe avant les valeurs en direct : c'est le geste
          // qu'on cherche avant de partir, les mesures ne sont qu'un contrôle.
          RecordingCard(recorder: _recorder, store: widget.rides),
          const SizedBox(height: 12),
          LiveValuesCard(hub: _hub, drivetrain: _drivetrain),
          const SizedBox(height: 12),
          RadarCard(hub: _hub),
          const SizedBox(height: 16),
          if (known.isNotEmpty) ...[
            _sectionTitle('Mes capteurs'),
            for (final device in known) _knownTile(device),
            const SizedBox(height: 16),
          ],
          if (pending.isNotEmpty) ...[
            _sectionTitle('Connexion en cours'),
            for (final connection in pending) _connectionTile(connection),
            const SizedBox(height: 16),
          ],
          _sectionTitle(_scanning ? 'Scan en cours…' : 'Appareils détectés'),
          if (discovered.isEmpty && !_scanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Réveille tes capteurs puis lance un scan.',
                  textAlign: TextAlign.center),
            ),
          for (final result in discovered) _scanTile(result),
          if (_recentFrames.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle('Trames brutes'),
            for (final frame in _recentFrames) _frameTile(frame),
          ],
        ],
      ),
    );
  }

  /// Dit ce qui manque aux seuils, quand il manque quelque chose.
  ///
  /// Reconstruit sur le magasin plutôt que sur un `setState` : le profil arrive
  /// pendant la navigation, donc pendant que cet écran est empilé dessous et ne
  /// se redessine pas de lui-même.
  Widget _thresholdGapCard() => ListenableBuilder(
        listenable: widget.riderProfile,
        builder: (context, _) {
          final gap = ThresholdGap.of(
            widget.riderProfile.profile,
            everReceived: widget.riderProfile.updatedAt != null,
          );
          if (gap == null) return const SizedBox.shrink();

          return Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.stacked_bar_chart),
              title: Text(gap.title),
              subtitle: Text(gap.detail),
              isThreeLine: true,
            ),
          );
        },
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  /// Un capteur mémorisé, connecté ou non.
  ///
  /// La ligne existe même quand l'appareil est éteint : c'est tout l'intérêt de
  /// s'en souvenir, on voit ce qui manque avant de partir.
  Widget _knownTile(KnownDevice known) {
    final connection = _hub.connectionFor(DeviceIdentifier(known.remoteId));

    Widget tile(SensorStatus? status) {
      final connected = status == SensorStatus.connected;
      // L'icône dit *ce qu'est* le capteur, la couleur dit s'il répond : deux
      // informations dans un seul point de l'écran, lisible en roulant.
      final color = connected
          ? Colors.teal
          : (status == null ? Colors.grey : Colors.orange);

      return ListTile(
        dense: true,
        leading: Icon(iconForDevice(known.kinds), color: color),
        title: Text(known.name.isEmpty ? '(sans nom)' : known.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SensorKindIcons(known.kinds),
            Text(_statusLabel(status, known)),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (action) => switch (action) {
            'forget' => _forget(known),
            'auto' => _devices.setAutoConnect(known.remoteId, !known.autoConnect),
            'connect' => _connect(
                BluetoothDevice.fromId(known.remoteId),
                label: known.name.isEmpty ? null : known.name,
              ),
            _ => null,
          },
          itemBuilder: (context) => [
            if (connection == null)
              const PopupMenuItem(value: 'connect', child: Text('Connecter')),
            PopupMenuItem(
              value: 'auto',
              child: Text(known.autoConnect
                  ? 'Ne plus connecter automatiquement'
                  : 'Connecter automatiquement'),
            ),
            const PopupMenuItem(value: 'forget', child: Text('Oublier')),
          ],
        ),
      );
    }

    if (connection == null) return tile(null);
    return ValueListenableBuilder<SensorStatus>(
      valueListenable: connection.status,
      builder: (context, status, _) => tile(status),
    );
  }

  String _statusLabel(SensorStatus? status, KnownDevice? known) {
    // Pas de connexion ouverte : l'appareil est simplement absent, ou on a
    // décidé de ne plus le solliciter.
    if (status == null) {
      return known?.autoConnect == false
          ? 'connexion auto désactivée'
          : 'hors ligne';
    }
    return switch (status) {
      SensorStatus.connected => 'connecté',
      SensorStatus.connecting => 'connexion…',
      SensorStatus.reconnecting => 'reconnexion…',
      SensorStatus.disconnected => 'déconnecté',
      SensorStatus.failed => 'échec',
    };
  }

  Widget _connectionTile(SensorConnection connection) {
    return ValueListenableBuilder<SensorStatus>(
      valueListenable: connection.status,
      builder: (context, status, _) => ValueListenableBuilder<Set<SensorKind>>(
        // Les capacités n'arrivent qu'à la découverte des services : l'icône
        // passe donc du bluetooth générique au capteur reconnu en cours de
        // connexion.
        valueListenable: connection.detectedKinds,
        builder: (context, kinds, _) => ListTile(
          dense: true,
          leading: Icon(
            iconForDevice(kinds),
            color:
                status == SensorStatus.connected ? Colors.teal : Colors.orange,
          ),
          title: Text(connection.name.isEmpty ? '(sans nom)' : connection.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (kinds.isNotEmpty) SensorKindIcons(kinds),
              Text(_statusLabel(status, null)),
            ],
          ),
          isThreeLine: kinds.isNotEmpty,
        ),
      ),
    );
  }

  Widget _scanTile(ScanResult result) {
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
    // Ce que l'appareil annonce savoir faire — indicatif seulement, plusieurs
    // capteurs (dont le Di2) n'annoncent pas leur service propriétaire.
    final kinds = kindsFromServices(result.advertisementData.serviceUuids);

    return ListTile(
      dense: true,
      leading: Icon(iconForDevice(kinds), color: Colors.grey),
      title: Text(name.isEmpty ? '(sans nom)' : name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${result.device.remoteId} · ${result.rssi} dBm'),
          if (kinds.isNotEmpty) SensorKindIcons(kinds),
        ],
      ),
      isThreeLine: kinds.isNotEmpty,
      trailing: const Icon(Icons.link),
      onTap: () => _connect(result.device, label: name),
    );
  }

  Widget _frameTile(RawFrame frame) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        frame.hex,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }
}
