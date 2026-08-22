import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'gps_fix.dart';

/// D'où viennent les positions pendant un enregistrement.
///
/// L'abstraction n'est pas de la décoration : elle est ce qui rend
/// [RideRecorder] testable sans appareil. L'implémentation réelle
/// ([GeolocatorGpsSource]) est le seul endroit du dossier qui touche à un
/// greffon de plateforme.
abstract class GpsSource {
  /// Vérifie que la position est effectivement disponible, en demandant
  /// l'autorisation si besoin. Lève [GpsUnavailable] sinon.
  Future<void> ensureReady();

  /// Le flux de positions. Un abonnement démarre le récepteur, l'annuler
  /// l'arrête.
  Stream<GpsFix> watch();
}

/// Position indisponible, avec le message à montrer au cycliste.
class GpsUnavailable implements Exception {
  const GpsUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// La position réelle du téléphone, via `geolocator`.
class GeolocatorGpsSource implements GpsSource {
  const GeolocatorGpsSource();

  @override
  Future<void> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const GpsUnavailable(
          'Active la localisation du téléphone pour enregistrer.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const GpsUnavailable(
          'Sans autorisation de position, il n\'y a pas de trace à enregistrer.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const GpsUnavailable(
          'Position refusée définitivement : autorise-la dans les réglages '
          'Android de l\'appli.');
    }

    // Android 13+ : la notification du service au premier plan ne s'affiche pas
    // sans cette autorisation. On la demande sans en faire une condition —
    // refusée, l'enregistrement fonctionne, il est seulement moins visible.
    if (Platform.isAndroid) await Permission.notification.request();
  }

  @override
  Stream<GpsFix> watch() =>
      Geolocator.getPositionStream(locationSettings: _settings()).map(_toFix);

  /// Un point par seconde, sans filtre de distance.
  ///
  /// `distanceFilter: 0` est délibéré : à l'arrêt à un feu, un filtre de
  /// distance couperait le flux, et avec lui le cardio et la puissance qui sont
  /// écrits au rythme des tics. On veut une seconde enregistrée par seconde
  /// écoulée, immobile ou non.
  ///
  /// Sur Android, la configuration de notification fait tourner la localisation
  /// dans un *foreground service* : la trace continue écran éteint ou appli
  /// passée en arrière-plan, ce qui est la situation normale d'un téléphone au
  /// guidon. Ce n'est pas une immunité absolue — Android peut toujours tuer le
  /// processus sous pression mémoire — mais c'est ce qui l'en dissuade, et le
  /// verrou de réveil empêche le processeur de dormir entre deux trames BLE.
  LocationSettings _settings() {
    if (!Platform.isAndroid) {
      return const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );
    }

    return AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Sports Scope',
        notificationText: 'Enregistrement de la sortie en cours',
        notificationChannelName: 'Enregistrement',
        enableWakeLock: true,
        // La notification ne se balaie pas : elle est le témoin qu'une sortie
        // tourne. La faire disparaître laisserait croire que l'enregistrement
        // s'est arrêté.
        setOngoing: true,
      ),
    );
  }

  GpsFix _toFix(Position position) => GpsFix(
        at: position.timestamp,
        lat: position.latitude,
        lng: position.longitude,
        // `altitude` vaut 0 quand l'appareil n'en fournit pas : à confondre
        // avec le niveau de la mer, on inventerait un dénivelé.
        altitudeM: position.altitude == 0 ? null : position.altitude,
        speedMps: position.speed.isFinite && position.speed >= 0
            ? position.speed
            : null,
        // `heading` vaut 0 quand le récepteur n'a pas de course à donner (à
        // l'arrêt) — indiscernable d'un vrai plein nord. On ne le retient donc
        // que strictement positif : perdre le nord exact une fois par sortie
        // coûte moins qu'annoncer « nord » à chaque feu rouge.
        headingDeg: position.heading.isFinite && position.heading > 0
            ? position.heading
            : null,
        accuracyM: position.accuracy > 0 ? position.accuracy : null,
        isMocked: position.isMocked,
      );
}
