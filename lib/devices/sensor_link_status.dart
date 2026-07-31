import 'package:flutter/material.dart';

import '../ble/sensor_connection.dart';

/// La couleur d'un capteur : **vert connecté, orange sinon**, gris quand on a
/// décidé de ne plus s'y reconnecter.
///
/// Deux états pour ce que fait le capteur, et pas trois : « pas de connexion
/// ouverte », « en cours » et « échec » se ressemblent trop pour mériter chacun
/// sa couleur — ce qu'on lit d'un coup d'œil avant de partir, c'est *est-ce que
/// ce capteur mesurera quelque chose*, et la réponse est oui ou non. Le détail
/// est en toutes lettres dans [sensorStatusLabel], sur la page des capteurs.
///
/// Le gris, lui, ne dit pas un état mais une **décision** : ce capteur-là ne
/// sera pas rattrapé, on l'a voulu. L'orange serait un reproche, et on
/// chercherait une panne qui n'existe pas — c'est précisément ce qui est arrivé
/// avec un Di2 dont la connexion auto avait été coupée par mégarde. La barre
/// (voir `SensorLinkDot`) redouble la couleur : sur un guidon au soleil, gris
/// et orange se confondent.
///
/// Un capteur connecté reste vert même écarté : il mesure *maintenant*, et
/// c'est la reconnexion **future** qu'on a désactivée.
///
/// Le vert est le teal du thème, pas un vert franc : c'est déjà la couleur de
/// « ça répond » sur l'icône de compte.
Color sensorLinkColor(SensorStatus? status, {bool autoConnect = true}) {
  if (status == SensorStatus.connected) return Colors.teal;
  return autoConnect ? Colors.orange : Colors.grey;
}

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
