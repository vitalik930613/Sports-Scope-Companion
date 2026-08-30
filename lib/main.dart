import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'account/account_page.dart';
import 'account/rider_profile_store.dart';
import 'training/training_budget_store.dart';
import 'account/site_session.dart';
import 'account/threshold_gap.dart';
import 'ble/sensor_hub.dart';
import 'dashboard/companion_settings_fetch.dart';
import 'dashboard/companion_settings_store.dart';
import 'dashboard/preset_picker.dart';
import 'dashboard/ride_preset.dart';
import 'devices/battery_status_card.dart';
import 'devices/device_linker.dart';
import 'devices/gatt_sniff_page.dart';
import 'devices/known_devices_store.dart';
import 'devices/sensor_status_strip.dart';
import 'devices/sensors_page.dart';
import 'drivetrain.dart';
import 'navigation/handoff_exchange.dart';
import 'navigation/navigation_picker_sheet.dart';
import 'navigation/navigation_target.dart';
import 'navigation/route_catalog_fetch.dart';
import 'navigation/route_catalog_store.dart';
import 'phone/debug_log_page.dart';
import 'phone/phone_sensors.dart';
import 'phone/rider_compass.dart';
import 'ride/battery_status.dart';
import 'ride/climb_debug_page.dart';
import 'ride/radar_debug_page.dart';
import 'ride/ride_shell_page.dart';
import 'recording/gps_source.dart';
import 'recording/recording_card.dart';
import 'recording/ride_recorder.dart';
import 'recording/ride_store.dart';
import 'recording/rides_page.dart';
import 'training_program/training_program.dart';
import 'training_program/training_program_catalog_store.dart';
import 'training_program/training_program_fetch.dart';
import 'training_program/workout_picker_sheet.dart';
import 'ui/metric_tile.dart';
import 'ui/radar_card.dart';
import 'update/update_card.dart';
import 'update/update_checker.dart';

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
  // Le budget de charge est relu pour la même raison, et une de plus : c'est
  // précisément la sortie qui part sans réseau — en montagne, un dimanche matin —
  // où l'on se demande jusqu'où pousser.
  final trainingBudget = await TrainingBudgetStore.open();
  // Et les itinéraires du compte, pour la même raison encore : on choisit son
  // tracé au départ, c'est-à-dire à l'endroit de la sortie où le réseau manque
  // le plus souvent.
  final routes = await RouteCatalogStore.open();
  // Les programmes d'entraînement, même raison que les itinéraires : on en
  // choisit un au départ, ou en pleine sortie, sac au dos, sans réseau.
  final trainingPrograms = await TrainingProgramCatalogStore.open();
  // Les profils de sortie, enfin : ils décident du tableau de bord et des
  // capteurs, donc ils doivent être là avant le premier écran — et surtout avant
  // qu'on puisse lancer un enregistrement depuis l'accueil.
  final settings = await CompanionSettingsStore.open();
  runApp(SportsScopeApp(
    devices: devices,
    rides: rides,
    session: session,
    riderProfile: riderProfile,
    trainingBudget: trainingBudget,
    routes: routes,
    trainingPrograms: trainingPrograms,
    settings: settings,
  ));
}

class SportsScopeApp extends StatefulWidget {
  const SportsScopeApp({
    super.key,
    required this.devices,
    required this.rides,
    required this.session,
    required this.riderProfile,
    required this.trainingBudget,
    required this.routes,
    required this.trainingPrograms,
    required this.settings,
  });

  final KnownDevicesStore devices;
  final RideStore rides;
  final RouteCatalogStore routes;

  /// Les programmes d'entraînement du compte — même rôle que [routes], pour
  /// le sélecteur du FAB « Entraînement » et celui du menu ⋮ en pleine
  /// sortie.
  final TrainingProgramCatalogStore trainingPrograms;
  final SiteSession session;
  final RiderProfileStore riderProfile;

  /// Le budget de charge, tenu à jour par la page de navigation comme les
  /// seuils. Il appartient à l'application : une sortie ouverte par un lien
  /// entrant doit trouver le même.
  final TrainingBudgetStore trainingBudget;

  /// Les profils de sortie et celui qu'on a choisi.
  final CompanionSettingsStore settings;

  @override
  State<SportsScopeApp> createState() => _SportsScopeAppState();
}

class _SportsScopeAppState extends State<SportsScopeApp> {
  /// Le hub vit au-dessus des écrans : les capteurs restent connectés quand on
  /// passe de la page de diagnostic à la navigation, et un lien entrant peut
  /// ouvrir la navigation sans repasser par la page des capteurs.
  final _hub = SensorHub();

  /// Les capteurs du téléphone lui-même : baromètre (dénivelé), luminosité
  /// (éclairage) et boussole (cap à l'arrêt). Une seule façade, partagée — rien
  /// ne s'allume tant que personne ne s'abonne.
  final _phone = const AndroidPhoneSensors();

  /// L'enregistreur vit au même étage que le hub, et pour la même raison : une
  /// sortie commencée sur l'écran des capteurs doit continuer pendant toute la
  /// navigation, et survivre au retour en arrière.
  late final _recorder =
      RideRecorder(hub: _hub, store: widget.rides, phone: _phone);

  /// La boussole vit au niveau de l'application comme le hub, mais ne tourne
  /// que pendant la navigation : c'est la coquille de sortie qui l'allume et
  /// l'éteint (`RideShellPage`).
  late final _compass = RiderCompass(phone: _phone);

  /// Le rattachement des capteurs, au même étage encore : son balayage doit
  /// continuer pendant la sortie, là où un capteur qui décroche est le plus
  /// coûteux et où aucun écran ne peut le relancer.
  late final _linker = DeviceLinker(
    hub: _hub,
    devices: widget.devices,
    // Une fonction et non une valeur : le balayage tourne depuis le lancement,
    // et le profil se choisit plus tard, au départ.
    sensorsOf: () => widget.settings.preset.sensors,
  );

  final _navigatorKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  /// La sortie qu'on vient de quitter, pour que l'accueil sache la reproposer.
  ///
  /// À cet étage et pas dans l'accueil : la navigation s'ouvre aussi par un
  /// lien entrant, qui ne passe par aucun écran. Rien n'en est écrit sur
  /// disque, volontairement — au prochain lancement, la page peut avoir fini sa
  /// navigation, et une reprise gardée d'un jour sur l'autre proposerait un
  /// tracé qui n'existe plus (voir `RouteCatalogFetch`).
  final _resume = ValueNotifier<NavigationTarget?>(null);

  /// Le contrôle de mise à jour, à cet étage pour n'interroger le site **qu'une
  /// fois par lancement** : l'accueil se reconstruit à chaque retour de sortie,
  /// et un contrôle dans son `initState` rejouerait la requête à chaque
  /// aller-retour.
  final _updates = UpdateChecker();

  /// Le statut du dernier rafraîchissement des profils de sortie.
  ///
  /// Sur une install fraîche, le lancement à froid interroge le site **avant**
  /// qu'un lien entrant n'ait eu la chance de poser sa session (le
  /// `handoffToken` ne s'échange contre un cookie que dans le WebView de
  /// navigation, une fois la sortie ouverte) : ce premier appel répond alors
  /// `signedOut`, et le document reste vide pour toute la sortie qui suit.
  /// Garder ce statut permet à [_openLink] de savoir, au retour de cette
  /// sortie, qu'il vaut la peine de rattraper le document — plutôt que de
  /// refaire la requête à chaque lien alors qu'elle a déjà réussi.
  SettingsFetchStatus? _settingsStatus;

  @override
  void initState() {
    super.initState();
    _listenForLinks();
    _linker.start();
    // Sans `await` : le premier écran ne doit rien attendre du réseau, et être
    // hors ligne avant de partir est le cas banal.
    unawaited(_updates.check());
    unawaited(_refreshSettings());
  }

  /// Les profils de sortie, **une fois par lancement** en temps normal — comme
  /// le contrôle de version, et pas comme le catalogue d'itinéraires.
  ///
  /// Ces réglages changent au plus une fois par mois, alors que les itinéraires
  /// changent la veille d'une sortie : les accrocher au rafraîchissement du
  /// catalogue coûterait un chargement de WebView hors écran à chaque ouverture
  /// de la feuille de départ, pour un document identique.
  ///
  /// Un échec est **muet**, même convention que le contrôle de version : hors
  /// ligne avant de partir est le cas banal, le cache fait autorité, et « les
  /// réglages n'ont pas pu être relus » n'est pas une information à poser sur
  /// l'écran d'avant-départ. Le statut, lui, est gardé (voir [_settingsStatus])
  /// — c'est [_openLink] qui décide s'il vaut la peine de réessayer.
  Future<void> _refreshSettings() async {
    _settingsStatus = await refreshCompanionSettings(
      widget.settings,
      trainingBudget: widget.trainingBudget,
    );
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
    var target = NavigationTarget.parse(uri);
    if (target == null) {
      debugPrint('[links] lien ignoré : $uri');
      return;
    }

    // Un `handoffToken` dit que le site nous croit connectés — mais la session
    // qu'il porte ne s'ouvre normalement que dans le WebView de navigation
    // (`NavigationTarget.url`), une fois `RideShellPage` déjà monté. Si ce
    // lancement n'a, lui, jamais vu de session valide (install fraîche, ou
    // connexion faite entre-temps sur le site), `settings.select` ci-dessous
    // choisirait le profil sur un document encore vide et la sortie
    // démarrerait sur le profil de repli — précisément le bug rapporté.
    //
    // On échange donc le jeton nous-mêmes, ici, avant que quoi que ce soit ne
    // s'ouvre : ça laisse le temps de rafraîchir les profils avec une session
    // désormais valide, et de choisir le bon avant la première image de la
    // carte. Jamais si `_settingsStatus` est déjà `ok` : la session existait
    // alors avant ce lien, et le WebView de navigation fera l'échange lui-même
    // comme d'habitude — pas de round-trip de plus sur l'usage quotidien.
    if (target.handoffToken != null && _settingsStatus != SettingsFetchStatus.ok) {
      final handoffToken = target.handoffToken!;
      // Cet aller-retour peut prendre plusieurs secondes (deux WebViews hors
      // écran, l'un après l'autre) : sans rien à l'écran, ça se lit comme une
      // appli qui ne répond plus, alors qu'elle télécharge.
      final exchanged = await _withConnectingDialog(() async {
        final ok = await const HandoffExchange().run(handoffToken);
        if (ok) await _refreshSettings();
        return ok;
      });
      if (exchanged) target = target.withoutHandoffToken();
    }

    await openNavigation(
      _navigatorKey.currentContext,
      target: target,
      hub: _hub,
      devices: widget.devices,
      recorder: _recorder,
      compass: _compass,
      session: widget.session,
      riderProfile: widget.riderProfile,
      trainingBudget: widget.trainingBudget,
      routes: widget.routes,
      trainingPrograms: widget.trainingPrograms,
      settings: widget.settings,
      resume: _resume,
      // Filet : si l'échange ci-dessus a échoué (hors ligne, jeton déjà
      // périmé) ou n'a pas eu lieu, `target` garde son jeton et le WebView de
      // navigation va tenter l'échange lui-même en roulant. S'il aboutit, la
      // session n'existera qu'au retour de cette sortie — c'est là qu'il vaut
      // la peine de rattraper les profils pour la prochaine fois.
      onHandoffRideEnded: _refreshSettings,
    );
  }

  /// Une boîte non interactive, le temps d'une action réseau qu'on ne peut pas
  /// éviter avant d'ouvrir la sortie (voir [_openLink]).
  ///
  /// `showDialog` insère sa route de façon synchrone — c'est ce qui permet de
  /// la refermer par un simple `pop()` juste après [action], sans jamais avoir
  /// laissé passer une image sans elle. Pas de bouton, pas de retour système
  /// (`PopScope(canPop: false)`) : rien à faire d'autre qu'attendre, et il ne
  /// faut pas qu'un appui malheureux abandonne l'échange en cours.
  Future<T> _withConnectingDialog<T>(Future<T> Function() action) async {
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return action();

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 20),
              Expanded(child: Text('Connexion à ton compte…')),
            ],
          ),
        ),
      ),
    ));

    try {
      return await action();
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _updates.dispose();
    _resume.dispose();
    _linker.dispose();
    unawaited(_compass.stop());
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
      home: HomePage(
        devices: widget.devices,
        settings: widget.settings,
        hub: _hub,
        linker: _linker,
        recorder: _recorder,
        compass: _compass,
        rides: widget.rides,
        session: widget.session,
        riderProfile: widget.riderProfile,
        trainingBudget: widget.trainingBudget,
        routes: widget.routes,
        trainingPrograms: widget.trainingPrograms,
        resume: _resume,
        updates: _updates,
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
  required KnownDevicesStore devices,
  required RideRecorder recorder,
  required RiderCompass compass,
  required SiteSession session,
  required RiderProfileStore riderProfile,
  required TrainingBudgetStore trainingBudget,
  required RouteCatalogStore routes,
  required TrainingProgramCatalogStore trainingPrograms,
  required CompanionSettingsStore settings,
  required ValueNotifier<NavigationTarget?> resume,
  /// Appelé au retour de la sortie, mais seulement si [target] porte encore un
  /// [NavigationTarget.handoffToken] à ce moment-là.
  ///
  /// C'est un **filet**, pas le chemin normal : `_openLink` échange déjà le
  /// jeton lui-même avant d'appeler cette fonction quand c'est nécessaire (voir
  /// `HandoffExchange`), et retire alors [NavigationTarget.handoffToken] de
  /// `target` — auquel cas ce callback ne sert plus à rien pour cette sortie.
  /// S'il reste malgré tout un jeton ici (l'échange préalable a échoué : hors
  /// ligne, jeton déjà périmé), c'est que le WebView de navigation a fait
  /// l'échange lui-même en roulant ; si une session s'est ouverte comme ça,
  /// c'est seulement à ce retour qu'elle a une chance d'avoir servi, d'où le
  /// rattrapage ici plutôt qu'avant. `null` pour un appel qui ne vient pas d'un
  /// lien entrant (feuille de départ, reprise) : là, la session — s'il y en a
  /// une — était déjà connue avant d'ouvrir la sortie, rien à rattraper.
  Future<void> Function()? onHandoffRideEnded,
}) async {
  if (context == null || !context.mounted) return;

  // Le profil choisi sur le site (modale de la page de partage) prime sur celui
  // déjà retenu dans l'appli : c'est un choix plus frais, fait pour CETTE sortie.
  // Une clé inconnue (profil supprimé depuis) ne fait pas échouer — `select`
  // retombe sur le premier profil, comme n'importe quelle clé périmée.
  if (target.presetKey != null) {
    await settings.select(target.presetKey!);
    if (!context.mounted) return;
  }

  // Programme d'entraînement couplé au lien (`?workout=<token>`), avec ou
  // sans itinéraire — pas un sous-mode de la navigation, une cible à part que
  // `RideRecorder` porte. Résolu et attaché AVANT de démarrer
  // l'enregistrement ci-dessous : c'est ce qui permet à `RideRecorder.start`
  // de déclarer `workoutLapSeries` dès le premier tour 0 plutôt que d'avoir à
  // toucher `preset.lapSeries`. Un jeton introuvable (programme supprimé
  // depuis, site injoignable) laisse simplement la sortie partir sans lui —
  // même tolérance que pour un `presetKey` inconnu.
  if (target.workoutToken != null) {
    final program = await fetchSharedTrainingProgram(target.workoutToken!);
    if (!context.mounted) return;
    if (program != null) recorder.startWorkout(program);
  }

  final preset = settings.preset;

  // La permission n'est demandée que si quelque chose s'en sert. Un profil de
  // home-trainer n'a ni carte à suivre ni trace à écrire : lui réclamer la
  // position serait une question sans objet, et la refuser bloquerait une sortie
  // qui n'en a pas besoin.
  if (preset.hasMap || preset.sensors.gps) {
    final status = await Permission.location.request();
    if (!context.mounted) return;

    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sans autorisation de position, la navigation ne peut pas '
            'te suivre.'),
      ));
      return;
    }
  }

  // `autoRecord` vient de la même modale : un choix déjà fait sur le site n'a
  // pas à être reposé au guidon. `null` (lien plus ancien, navigation choisie
  // dans l'appli) garde la question ; `false` la saute sans démarrer ; `true`
  // démarre directement, comme si le cycliste avait répondu « Enregistrer ».
  if (!recorder.isActive) {
    if (target.autoRecord == true) {
      await _startRecording(context, recorder, preset.sensors, preset.lapSeries);
    } else if (target.autoRecord == null) {
      await _offerRecording(context, recorder, preset.sensors, preset.lapSeries);
    }
    if (!context.mounted) return;
  }

  final left = await Navigator.of(context).push<NavigationTarget>(
    MaterialPageRoute(
      builder: (_) => RideShellPage(
        target: target,
        preset: preset,
        hub: hub,
        devices: devices,
        // La boussole ne sert qu'avec une carte, et le profil peut la couper.
        compass: preset.sensors.compass ? compass : null,
        // Indépendant de la ligne ci-dessus : la batterie du téléphone n'a
        // pas de réglage pour la couper (voir `RideShellPage.phone`), elle ne
        // doit pas disparaître avec la boussole.
        phone: compass.phone,
        recorder: recorder,
        session: session,
        riderProfile: riderProfile,
        trainingBudget: trainingBudget,
        routes: routes,
        trainingPrograms: trainingPrograms,
        // Ce que le tableau de bord mesure part au site au prochain
        // rafraîchissement : son éditeur cesse alors de supposer un téléphone.
        onGridMeasured: settings.recordGrid,
      ),
    ),
  );

  // Ce que la coquille rend en partant : de quoi rouvrir la sortie là où on
  // l'a laissée. C'est la contrepartie du départ sans confirmation — rentrer
  // ne coûte qu'un tap, repartir non plus.
  if (left != null) resume.value = left;

  // La session que le jeton de ce lien a pu ouvrir n'existait pas encore
  // avant la sortie (voir la doc de [onHandoffRideEnded]) : c'est seulement
  // maintenant qu'elle a une chance d'avoir servi.
  if (target.handoffToken != null) await onHandoffRideEnded?.call();
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
  SensorSettings sensors,
  Set<String> lapSeries,
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

  await _startRecording(context, recorder, sensors, lapSeries);
}

/// Démarre l'enregistrement, et dit si ça a échoué. Séparé de [_offerRecording]
/// pour que le choix fait sur le site (`autoRecord: true`) puisse démarrer
/// directement, sans reposer la question que la modale du site vient de poser.
Future<void> _startRecording(
  BuildContext context,
  RideRecorder recorder,
  SensorSettings sensors,
  Set<String> lapSeries,
) async {
  try {
    await recorder.start(sensors: sensors, lapSeries: lapSeries);
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

/// L'accueil : partir rouler, et voir avant de partir que tout répond.
///
/// Ce n'est ni l'écran de sortie — la navigation est dans [RideShellPage] — ni
/// l'écran d'appairage, qui est une sous-page ([SensorsPage]). Ici on trouve le
/// bouton « Naviguer », l'état des capteurs connus en une rangée d'icônes, et
/// les quelques cartes qui disent ce qui manquera sur la route (session du
/// site, seuils, enregistrement).
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.devices,
    required this.hub,
    required this.linker,
    required this.recorder,
    required this.compass,
    required this.rides,
    required this.session,
    required this.riderProfile,
    required this.trainingBudget,
    required this.routes,
    required this.trainingPrograms,
    required this.settings,
    required this.resume,
    required this.updates,
  });

  final KnownDevicesStore devices;

  /// Les profils de sortie. Cet écran ne les affiche pas : il les passe au
  /// sélecteur de départ, seul endroit où l'on choisit son vélo, et à
  /// l'enregistrement lancé d'ici, qui doit partir avec les mêmes capteurs.
  final CompanionSettingsStore settings;

  /// La sortie qu'on vient de quitter, s'il y en a une. Elle appartient à
  /// l'application et non à cet écran : un lien entrant ouvre la navigation
  /// sans passer par ici, et sa sortie doit se retrouver dans la même carte.
  final ValueNotifier<NavigationTarget?> resume;

  /// Le rattachement des capteurs. Il appartient à l'application : son
  /// balayage doit continuer pendant la sortie, écran empilé par-dessus.
  final DeviceLinker linker;

  /// Les itinéraires du compte, pour le sélecteur de navigation.
  final RouteCatalogStore routes;

  /// Les programmes d'entraînement du compte, pour le FAB « Entraînement ».
  final TrainingProgramCatalogStore trainingPrograms;

  /// Le hub appartient à l'application, pas à cet écran : les capteurs doivent
  /// rester connectés quand on passe en navigation.
  final SensorHub hub;

  /// L'enregistreur, pour la même raison que le hub.
  final RideRecorder recorder;

  /// La boussole, pour la même raison encore — et parce qu'elle ne s'allume
  /// qu'une fois la navigation ouverte.
  final RiderCompass compass;

  final RideStore rides;

  /// La session du site, partagée avec la navigation : elle appartient à
  /// l'application, pas à cet écran.
  final SiteSession session;

  /// Les seuils du cycliste, transmis à la navigation qui les tient à jour
  /// depuis le site. Cet écran ne les affiche pas, il signale seulement ce qui
  /// leur manque pour que les zones du bandeau de sortie existent.
  final RiderProfileStore riderProfile;

  /// Le budget de charge, transmis à la navigation qui le tient à jour depuis le
  /// site. Cet écran ne l'affiche pas — un budget se lit en roulant, pas avant.
  final TrainingBudgetStore trainingBudget;

  /// Le contrôle de mise à jour, interrogé une fois au lancement par
  /// l'application. Cet écran ne fait que montrer son résultat, quand il y en a
  /// un.
  final UpdateChecker updates;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _drivetrain = Drivetrain.road;

  var _adapterState = BluetoothAdapterState.unknown;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  /// Le seuil vient du profil actif au moment où l'accueil se construit —
  /// pas recalculé si on change de profil sans relancer l'appli, même
  /// simplification que le reste de cet écran (la liste de capteurs qu'un
  /// profil garde, par exemple, ne se relit pas non plus en direct ici).
  // Pas de `phone:` ici, volontairement : cette carte n'existe que si un
  // capteur BLE est connu (voir la tête de `BatteryStatusCard`), et la
  // batterie du téléphone se lit déjà dans la barre système de l'accueil —
  // c'est en sortie, plein écran, qu'elle disparaît (voir `RideShellPage`).
  late final _battery = BatteryStatusNotifier(
    widget.devices,
    widget.hub,
    thresholdPercent: widget.settings.preset.battery.thresholdPercent,
  );

  KnownDevicesStore get _devices => widget.devices;
  SensorHub get _hub => widget.hub;
  RideRecorder get _recorder => widget.recorder;

  void _openSensors() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SensorsPage(
        devices: _devices,
        hub: _hub,
        linker: widget.linker,
      ),
    ));
  }

  void _openRides() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RidesPage(
        store: widget.rides,
        recorder: _recorder,
        riderProfile: widget.riderProfile,
      ),
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

  /// Le banc d'essai du col : juger la pastille et le graphique gradué sans
  /// attendre de grimper un vrai col.
  void _openClimbDebug() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ClimbDebugPage(),
    ));
  }

  /// Banc d'essai temporaire, le temps d'identifier la caractéristique D-Fly
  /// des boutons Di2 — voir `devices/gatt_sniff_page.dart`.
  void _openGattSniff() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GattSniffPage(hub: _hub),
    ));
  }

  /// Banc d'essai temporaire, le temps de vérifier en sortie la détection de
  /// dérive de la boussole — voir `phone/debug_log_page.dart`. Utile en
  /// particulier loin de tout `adb` : le journal reste lisible sur le
  /// téléphone, et se copie pour être renvoyé une fois rentré.
  void _openDebugLog() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const DebugLogPage(),
    ));
  }

  /// L'écran Compte, et **ce qu'il faut aller chercher au retour**.
  ///
  /// La page rend `true` quand la connexion vient d'aboutir. Ça n'est pas une
  /// politesse : tout ce que le site réserve aux connectés a été demandé en vain
  /// jusque-là — la liste d'itinéraires est vide, les profils de sortie sont
  /// restés sur le tableau de bord intégré. Sans ce rattrapage, il fallait
  /// relancer l'appli pour que la connexion serve à quelque chose, ou ouvrir la
  /// feuille de départ en espérant qu'elle rafraîchisse.
  Future<void> _openAccount() async {
    final justSignedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AccountPage(session: widget.session)),
    );

    if (justSignedIn != true || !mounted) return;
    await _fetchWhatTheSessionUnlocks();
  }

  /// Les deux choses que seule une session ouverte permet de lire.
  ///
  /// En parallèle : ce sont deux WebViews hors écran indépendants, et les
  /// enchaîner doublerait l'attente devant un écran qui vient déjà de changer.
  ///
  /// Les échecs sont **muets**, comme partout ailleurs : le cache fait autorité,
  /// et « le rafraîchissement a échoué » n'est pas une information à poser sur
  /// l'écran d'avant-départ. Ce qui se dit, en revanche, c'est la connexion
  /// elle-même — c'est ce que le cycliste vient de faire, et il doit savoir que
  /// ça a pris.
  Future<void> _fetchWhatTheSessionUnlocks() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Connecté — récupération de tes itinéraires…'),
      duration: Duration(seconds: 2),
    ));

    await Future.wait([
      _fetchRoutes(),
      refreshCompanionSettings(
        widget.settings,
        trainingBudget: widget.trainingBudget,
      ),
    ]);
  }

  Future<void> _fetchRoutes() async {
    final result = await const RouteCatalogFetch().run();
    if (result.status != RouteFetchStatus.ok) return;
    await widget.routes.record(result.routes);
  }

  @override
  void initState() {
    super.initState();

    // La navigation, elle aussi, constate l'état de la session : revenir d'une
    // sortie doit rafraîchir le bandeau ici.
    widget.session.addListener(_onSessionChanged);

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
      // Rien à rafraîchir à la main derrière : la rangée de capteurs se
      // reconstruit sur le magasin, et un capteur qui répond y est réécrit
      // (`remember`) au moment même où il passe à « connecté ».
      if (state == BluetoothAdapterState.on) {
        unawaited(widget.linker.reconnectKnown());
      }
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _adapterSub?.cancel();
    _battery.dispose();
    // Le hub n'est pas fermé ici : il survit à cet écran.
    super.dispose();
  }

  void _onSessionChanged() {
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
      builder: (_) => NavigationPickerSheet(
        catalog: widget.routes,
        settings: widget.settings,
      ),
    );

    if (target == null || !mounted) return;
    await _navigate(target);
  }

  /// Démarrer un programme d'entraînement seul, sans itinéraire — le cas du
  /// home-trainer ou de la course à pied. Distinct de [_chooseNavigation] :
  /// un programme n'est pas un sous-mode de la navigation, il a son propre
  /// bouton d'accueil. (Le coupler à un itinéraire se choisit côté site,
  /// dans la modale « Ouvrir dans l'application » d'un itinéraire — le lien
  /// qui en sort porte alors `?workout=` en plus du jeton de route, et c'est
  /// [openNavigation] qui le résout.)
  ///
  /// Le programme est déjà résolu (pas qu'un jeton) en sortie de la feuille :
  /// [WorkoutPickerSheet] l'a fait en le choisissant, pas la peine de le
  /// redemander au site.
  Future<void> _startWorkout() async {
    final program = await showModalBottomSheet<TrainingProgram>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WorkoutPickerSheet(catalog: widget.trainingPrograms),
    );

    if (program == null || !mounted) return;
    widget.recorder.startWorkout(program);
    await _navigate(const NavigationTarget.free());
  }

  /// Choisir le profil de la sortie, depuis l'accueil plutôt que depuis le
  /// sélecteur de navigation : c'est le geste qu'on fait en premier — on
  /// choisit son vélo avant son itinéraire — et il doit rester possible sans
  /// même viser « Naviguer », pour l'enregistrement lancé d'ici.
  Future<void> _choosePreset() async {
    await choosePreset(context, widget.settings);
    if (mounted) setState(() {});
  }

  Future<void> _navigate(NavigationTarget target) => openNavigation(
        context,
        target: target,
        hub: _hub,
        devices: widget.devices,
        recorder: widget.recorder,
        compass: widget.compass,
        session: widget.session,
        riderProfile: widget.riderProfile,
        trainingBudget: widget.trainingBudget,
        routes: widget.routes,
        trainingPrograms: widget.trainingPrograms,
        settings: widget.settings,
        resume: widget.resume,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports Scope'),
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
            onPressed: _openSensors,
            icon: const Icon(Icons.sensors),
            tooltip: 'Capteurs',
          ),
          // Bancs d'essai et journal : utiles en développement, pas au
          // quotidien — regroupés pour ne pas noyer les boutons qu'on touche
          // à chaque sortie (Compte, Mes sorties, Capteurs).
          PopupMenuButton<VoidCallback>(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug',
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _openRadarSimulator,
                child: const ListTile(
                  leading: Icon(Icons.radar),
                  title: Text('Simuler le radar'),
                ),
              ),
              PopupMenuItem(
                value: _openClimbDebug,
                child: const ListTile(
                  leading: Icon(Icons.landscape),
                  title: Text('Simuler un col'),
                ),
              ),
              PopupMenuItem(
                value: _openGattSniff,
                child: const ListTile(
                  leading: Icon(Icons.bug_report),
                  title: Text('Sniff GATT (D-Fly)'),
                ),
              ),
              PopupMenuItem(
                value: _openDebugLog,
                child: const ListTile(
                  leading: Icon(Icons.terminal),
                  title: Text('Journal'),
                ),
              ),
            ],
          ),
        ],
      ),
      // Le profil d'abord, la navigation ensuite : c'est l'ordre du geste sur
      // la route (on choisit son vélo avant son itinéraire), et Naviguer part
      // avec le profil déjà choisi plutôt que de le redemander en route.
      // Aucun des deux boutons ne joue son animation Hero — sans `heroTag`
      // explicite, deux FAB visibles à la fois partagent le même tag par
      // défaut et Flutter refuse de construire la page.
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.settings.hasChoice) ...[
            FloatingActionButton.extended(
              heroTag: 'choosePreset',
              onPressed: _choosePreset,
              icon: presetLeading(widget.settings.preset),
              label: Text(widget.settings.preset.name),
            ),
            const SizedBox(width: 12),
          ],
          FloatingActionButton.extended(
            heroTag: 'navigate',
            onPressed: _chooseNavigation,
            icon: const Icon(Icons.navigation),
            label: const Text('Naviguer'),
          ),
          const SizedBox(width: 12),
          // Icône seule, pas « extended » comme les deux précédents : un
          // programme d'entraînement est un départ moins fréquent qu'une
          // navigation, il n'a pas à réclamer autant de largeur sur un petit
          // écran déjà partagé entre deux ou trois boutons.
          FloatingActionButton(
            heroTag: 'workout',
            onPressed: _startWorkout,
            tooltip: 'Entraînement',
            child: const Icon(Icons.timer_outlined),
          ),
        ],
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
          // En tête de tout : quand on revient d'une sortie, c'est la seule
          // chose qu'on est venu chercher une fois le coup d'œil donné.
          _resumeCard(),
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
          if (widget.session.signedIn != false) _thresholdsCard(),
          // Avec les autres cartes « ce qu'il faudrait régler avant de partir »,
          // et pas en tête : une mise à jour n'empêche jamais de rouler. Elle
          // ne s'affiche que s'il y en a une, et l'installation se fait dans le
          // navigateur — donc pas en pleine préparation de sortie.
          UpdateCard(checker: widget.updates),
          // L'état des capteurs passe avant tout le reste : c'est la question
          // qu'on se pose au moment de partir, et la seule à laquelle il faut
          // répondre avant de rouler — un capteur oublié sur le vélo d'à côté
          // ne se rattrape pas en route.
          SensorStatusStrip(
            devices: _devices,
            hub: _hub,
            onTap: _openSensors,
          ),
          const SizedBox(height: 12),
          // Juste après : la rangée dit qui répond, cette carte dit combien
          // il leur reste. Invisible tant qu'aucun capteur n'est connu — même
          // geste (ouvrir la page Capteurs) que la rangée au-dessus, et pas de
          // gap manuel autour d'elle pour la même raison que `UpdateCard` /
          // `_thresholdsCard()` n'en ont pas : une carte parfois absente ne
          // doit pas laisser un blanc à sa place.
          BatteryStatusCard(battery: _battery, onTap: _openSensors),
          // L'enregistrement passe avant les valeurs en direct : c'est le geste
          // qu'on cherche avant de partir, les mesures ne sont qu'un contrôle.
          RecordingCard(
            recorder: _recorder,
            store: widget.rides,
            riderProfile: widget.riderProfile,
            sensors: widget.settings.preset.sensors,
            lapSeries: widget.settings.preset.lapSeries,
          ),
          const SizedBox(height: 12),
          LiveValuesCard(hub: _hub, drivetrain: _drivetrain),
          const SizedBox(height: 12),
          RadarCard(hub: _hub),
        ],
      ),
    );
  }

  /// Rouvrir la sortie qu'on vient de quitter, **en un tap et là où on en
  /// était**.
  ///
  /// C'est ce qui rend le retour à l'accueil sans conséquence : on descend voir
  /// l'enregistrement ou un capteur, on remonte. Sans elle, revenir coûtait le
  /// sélecteur, l'attente de sa lecture du stockage de la page, puis le choix
  /// du bon tracé — assez pour qu'on préfère ne pas rentrer du tout.
  ///
  /// La cible est une **reprise** ([NavigationTarget.resume]) : redemander
  /// l'itinéraire par son token rechargerait le tracé depuis son début, alors
  /// que la page, elle, a gardé où l'on en était.
  ///
  /// Rien avant la première sortie, et rien au lancement suivant : la carte
  /// n'existe que dans la mémoire de l'application, pour ne jamais proposer de
  /// reprendre un tracé que la page a fini depuis longtemps.
  Widget _resumeCard() => ValueListenableBuilder<NavigationTarget?>(
        valueListenable: widget.resume,
        builder: (context, target, _) {
          if (target == null) return const SizedBox.shrink();

          return Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.navigation),
              title: const Text('Reprendre la navigation'),
              subtitle: Text(
                target.label ?? 'Là où on en était.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigate(target),
            ),
          );
        },
      );

  /// FTP et LTHR telles que le site les connaît, et ce qui manque encore.
  ///
  /// Toujours affichée (dès qu'on est connecté) plutôt que seulement en cas de
  /// trou : c'est le seul endroit de l'appli où ces deux chiffres se lisent, le
  /// bandeau de sortie ne portant que les zones qui en découlent.
  ///
  /// Reconstruite sur le magasin plutôt que sur un `setState` : le profil arrive
  /// pendant la navigation, donc pendant que cet écran est empilé dessous et ne
  /// se redessine pas de lui-même.
  Widget _thresholdsCard() => ListenableBuilder(
        listenable: widget.riderProfile,
        builder: (context, _) {
          final profile = widget.riderProfile.profile;
          final gap = ThresholdGap.of(
            profile,
            everReceived: widget.riderProfile.updatedAt != null,
          );
          final ftp =
              profile.ftpWatts != null ? '${profile.ftpWatts} W' : '—';
          final lthr = profile.lthr != null ? '${profile.lthr} bpm' : '—';

          return Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.stacked_bar_chart),
              title: Text('FTP $ftp · LTHR $lthr'),
              subtitle: gap == null ? null : Text(gap.detail),
              isThreeLine: gap != null,
            ),
          );
        },
      );
}
