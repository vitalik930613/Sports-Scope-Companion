import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Rétroéclairage de la fenêtre de navigation.
///
/// La veille de la page web ne noircit que les pixels : elle garde son verrou
/// d'écran (sans quoi Android gèlerait le WebView, et avec lui la détection de
/// virage qui doit justement rallumer). L'écran reste donc alimenté — sur un
/// guidon en plein soleil c'est le premier poste de consommation, très loin
/// devant le GPS et le BLE.
///
/// Baisser le rétroéclairage au minimum ramène le coût d'un écran noir près de
/// celui d'un écran éteint, sans rien endormir : JavaScript, position et
/// alertes continuent de tourner, et la page redemande [systemDefault]
/// d'elle-même à l'approche d'un virage.
///
/// Un vrai écran éteint demanderait de sortir la position et la détection de
/// virage du WebView, dans un service de premier plan — un autre chantier.
class ScreenDimmer {
  ScreenDimmer({
    this._channel = const MethodChannel(channelName),
  });

  static const channelName = 'sports_scope/screen';

  final MethodChannel _channel;

  /// Niveau appliqué en veille. Volontairement non nul : la page continue
  /// d'afficher la distance au prochain virage sur son fond noir, et à zéro
  /// certains appareils coupent franchement le rétroéclairage — le bandeau
  /// deviendrait illisible même de nuit. Sur une dalle OLED le gain vient de
  /// toute façon surtout des pixels noirs.
  static const dimmed = 0.01;

  /// Rend la main au réglage système (`BRIGHTNESS_OVERRIDE_NONE` côté Android).
  static const systemDefault = -1.0;

  Future<void> dim() => setBrightness(dimmed);

  Future<void> restore() => setBrightness(systemDefault);

  Future<void> setBrightness(double level) async {
    try {
      await _channel.invokeMethod<void>('setBrightness', level);
    } on MissingPluginException {
      // Plateforme sans implémentation native : la navigation reste lisible,
      // simplement à la luminosité habituelle.
    } catch (e) {
      // La luminosité n'est jamais une raison d'interrompre une navigation.
      debugPrint('[screen] luminosité ignorée : $e');
    }
  }
}
