import 'package:flutter/material.dart';

import '../ble/sensor_connection.dart';

/// La couleur d'un capteur : **vert connecté, orange sinon**.
///
/// Deux états et pas trois : « pas de connexion ouverte », « en cours » et
/// « échec » se ressemblent trop pour mériter chacun sa couleur — ce qu'on lit
/// d'un coup d'œil avant de partir, c'est *est-ce que ce capteur mesurera
/// quelque chose*, et la réponse est oui ou non. Le détail est en toutes
/// lettres dans [sensorStatusLabel], sur la page des capteurs.
///
/// Le vert est le teal du thème, pas un vert franc : c'est déjà la couleur de
/// « ça répond » sur l'icône de compte.
Color sensorLinkColor(SensorStatus? status) =>
    status == SensorStatus.connected ? Colors.teal : Colors.orange;

/// L'état d'un capteur en toutes lettres.
///
/// [autoConnect] à faux change le sens de l'absence de connexion : le capteur
/// n'est pas injoignable, on a demandé à ne plus le solliciter. Sans cette
/// nuance, un appareil volontairement mis de côté se lirait comme une panne.
String sensorStatusLabel(SensorStatus? status, {bool autoConnect = true}) {
  if (status == null) {
    return autoConnect ? 'hors ligne' : 'connexion auto désactivée';
  }
  return switch (status) {
    SensorStatus.connected => 'connecté',
    SensorStatus.connecting => 'connexion…',
    SensorStatus.reconnecting => 'reconnexion…',
    SensorStatus.disconnected => 'déconnecté',
    SensorStatus.failed => 'échec',
  };
}
