import 'package:flutter/material.dart';

import '../ble/power_calibration.dart';
import '../ble/sensor_connection.dart';
import '../ble/sensor_hub.dart';
import '../ble/sensor_profile.dart';

/// Ce que la boîte de dialogue déclenche. Une fonction et pas une connexion :
/// la calibration se teste alors sans Bluetooth, et c'est la seule façon de
/// vérifier ce qui compte ici — que le résultat du capteur, quel qu'il soit,
/// arrive bien sous les yeux du cycliste.
typedef PowerCalibrationRunner = Future<PowerCalibrationResult> Function();

/// Le capteur qu'on calibrerait maintenant : puissance et connecté.
///
/// Le premier trouvé — un vélo n'a qu'un capteur de puissance, et poser la
/// question au bord de la route coûterait plus qu'elle ne rapporte.
SensorConnection? powerCalibrationTarget(SensorHub hub) {
  for (final connection in hub.connectionsWith(SensorKind.power)) {
    if (connection.status.value == SensorStatus.connected) return connection;
  }
  return null;
}

/// Vrai quand la calibration a un sens ici et maintenant.
///
/// Sert à décider si la commande **apparaît** : un capteur de puissance qui
/// n'expose pas de Control Point ne se calibre que par l'appli du constructeur,
/// et une commande qui ne peut que dire non n'a rien à faire dans un menu.
bool powerCalibrationAvailable(SensorHub hub) =>
    powerCalibrationTarget(hub)?.canCalibratePower.value ?? false;

/// Ouvre la calibration du capteur de puissance connecté.
///
/// Le même appel depuis l'écran des capteurs et depuis la sortie : c'est en
/// roulant qu'on s'aperçoit d'une puissance qui dérive, et redescendre de vélo
/// pour aller chercher un autre écran ferait renoncer.
Future<void> showPowerCalibration(BuildContext context,
        {required SensorHub hub}) =>
    showPowerCalibrationFor(context, powerCalibrationTarget(hub));

/// Ouvre la calibration d'un capteur **désigné**.
///
/// C'est ce que veut la page des capteurs : on y tape le menu d'une ligne
/// précise, et calibrer un autre boîtier que celui qu'on a sous le doigt serait
/// une trahison — même si, en pratique, il n'y en a qu'un.
Future<void> showPowerCalibrationFor(
  BuildContext context,
  SensorConnection? connection,
) {
  return showDialog<void>(
    context: context,
    // Une calibration dure une dizaine de secondes : un tap à côté ne doit pas
    // fermer la boîte avant que le capteur ait répondu, sinon on ne saura
    // jamais si elle a abouti.
    barrierDismissible: false,
    builder: (_) => PowerCalibrationDialog(
      sensorName: connection?.name ?? '',
      run: connection?.calibratePower,
    ),
  );
}

/// La calibration, de la consigne au résultat.
class PowerCalibrationDialog extends StatefulWidget {
  const PowerCalibrationDialog({
    super.key,
    required this.sensorName,
    this.run,
  });

  /// Nommé et pas seulement « le capteur » : on calibre un boîtier précis, et
  /// sur un vélo qui en porte plusieurs c'est la seule façon de savoir lequel.
  final String sensorName;

  /// `null` quand aucun capteur de puissance n'est connecté : la boîte le dit
  /// et ne propose rien, plutôt que d'offrir un bouton qui échouera.
  final PowerCalibrationRunner? run;

  @override
  State<PowerCalibrationDialog> createState() => _PowerCalibrationDialogState();
}

class _PowerCalibrationDialogState extends State<PowerCalibrationDialog> {
  var _running = false;
  PowerCalibrationResult? _result;

  Future<void> _calibrate() async {
    final run = widget.run;
    if (run == null || _running) return;

    setState(() {
      _running = true;
      // L'ancien résultat s'efface au départ : un « calibré » qui resterait
      // affiché pendant la deuxième tentative se lirait comme le sien.
      _result = null;
    });

    final result = await run();
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return AlertDialog(
      title: const Text('Calibrer la puissance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.run == null)
            const Text(
              'Aucun capteur de puissance connecté. Réveille-le, puis '
              'réessaie.',
            )
          else ...[
            Text(widget.sensorName.isEmpty
                ? 'Capteur de puissance'
                : widget.sensorName),
            const SizedBox(height: 12),
            // La consigne reste affichée pendant et après : c'est la cause
            // numéro un des calibrations ratées, et on la relit en général
            // *après* avoir vu l'échec.
            const Text(
              'Vélo à l\'arrêt et d\'aplomb, rien qui appuie sur les pédales — '
              'ni pied, ni main. Ne touche pas au vélo pendant la mesure.',
            ),
            if (_running) ...[
              const SizedBox(height: 20),
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Mesure en cours…')),
                ],
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 20),
              _resultLine(result),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          // Fermer reste possible pendant la mesure : la calibration se fait
          // dans le capteur, l'abandonner à l'écran ne l'interrompt pas.
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        if (widget.run != null)
          FilledButton(
            onPressed: _running ? null : _calibrate,
            child: Text(result == null ? 'Calibrer' : 'Recommencer'),
          ),
      ],
    );
  }

  Widget _resultLine(PowerCalibrationResult result) {
    final done = result is PowerCalibrationDone;
    final color = done ? Colors.teal : Theme.of(context).colorScheme.error;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(done ? Icons.check_circle : Icons.error_outline,
            color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(result.message, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
