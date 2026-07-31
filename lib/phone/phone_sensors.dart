import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ce que le téléphone sait mesurer de lui-même.
///
/// Les trois capteurs sont facultatifs et le restent : le baromètre manque sur
/// une bonne part des appareils d'entrée de gamme, et rien de ce dossier ne doit
/// cesser de fonctionner sans lui. D'où le `null` partout plutôt qu'une valeur
/// par défaut — voir [PhoneSensorAvailability].
class PhoneSensorAvailability {
  const PhoneSensorAvailability({
    this.pressure = false,
    this.light = false,
    this.heading = false,
  });

  final bool pressure;
  final bool light;
  final bool heading;

  @override
  String toString() =>
      'baromètre=$pressure lumière=$light boussole=$heading';
}

/// D'où viennent les mesures du téléphone.
///
/// L'abstraction est là pour la même raison que [GpsSource] : elle rend
/// testables sans appareil les pièces qui consomment ces flux. L'implémentation
/// réelle ([AndroidPhoneSensors]) est le seul endroit du dossier qui touche à un
/// canal de plateforme.
abstract class PhoneSensors {
  /// Ce que cet appareil possède réellement. À interroger une fois au démarrage :
  /// c'est ce qui permet de dire « pas de baromètre » plutôt que d'attendre en
  /// vain une mesure qui ne viendra jamais.
  Future<PhoneSensorAvailability> available();

  /// Pression atmosphérique, en hectopascals. Un abonnement allume le capteur,
  /// l'annuler l'éteint.
  Stream<double> pressureHpa();

  /// Luminosité ambiante, en lux.
  Stream<double> lux();

  /// Cap du téléphone, en degrés depuis le nord géographique (0 = nord).
  Stream<double> headingDeg();

  /// Donne au natif la position courante, dont il tire la déclinaison
  /// magnétique. Sans elle, [headingDeg] rend un cap magnétique — juste à
  /// quelques degrés près chez nous, faux de quinze ailleurs.
  Future<void> setLocation({
    required double lat,
    required double lng,
    double altitudeM = 0,
  });
}

/// Les capteurs réels, via le canal de plateforme (`PhoneSensors.kt`).
class AndroidPhoneSensors implements PhoneSensors {
  const AndroidPhoneSensors();

  static const _namespace = 'sports_scope/phone_sensors';
  static const _control = MethodChannel('$_namespace/control');
  static const _pressure = EventChannel('$_namespace/pressure');
  static const _light = EventChannel('$_namespace/light');
  static const _heading = EventChannel('$_namespace/heading');

  @override
  Future<PhoneSensorAvailability> available() async {
    try {
      final raw = await _control.invokeMapMethod<String, dynamic>('available');
      if (raw == null) return const PhoneSensorAvailability();
      return PhoneSensorAvailability(
        pressure: raw['pressure'] == true,
        light: raw['light'] == true,
        heading: raw['heading'] == true,
      );
    } catch (e) {
      // Canal absent : appareil non Android, ou test de widget sans moteur.
      // Aucun capteur vaut mieux qu'une exception au démarrage.
      debugPrint('[capteurs] inventaire indisponible : $e');
      return const PhoneSensorAvailability();
    }
  }

  @override
  Stream<double> pressureHpa() => _doubles(_pressure, 'pression');

  @override
  Stream<double> lux() => _doubles(_light, 'lumière');

  @override
  Stream<double> headingDeg() => _doubles(_heading, 'cap');

  @override
  Future<void> setLocation({
    required double lat,
    required double lng,
    double altitudeM = 0,
  }) async {
    try {
      await _control.invokeMethod<void>('setLocation', {
        'lat': lat,
        'lng': lng,
        'altitudeM': altitudeM,
      });
    } catch (e) {
      debugPrint('[capteurs] déclinaison non transmise : $e');
    }
  }

  /// Un flux qui **ne tombe jamais en erreur** : une trame illisible est sautée,
  /// une erreur de canal ferme le flux proprement. Un capteur qui déraille ne
  /// doit pas emporter l'enregistrement avec lui.
  static Stream<double> _doubles(EventChannel channel, String label) => channel
      .receiveBroadcastStream()
      .map((raw) => raw is num ? raw.toDouble() : double.nan)
      .where((value) => !value.isNaN)
      .handleError((Object e) => debugPrint('[capteurs] $label en erreur : $e'));
}
