import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/samples.dart';
import 'radar_alert_sound.dart';
import 'radar_severity.dart';
import 'radar_simulator.dart';
import 'widgets/map_edge_handle.dart';
import 'widgets/radar_distance_badges.dart';
import 'widgets/radar_frame.dart';
import 'widgets/radar_side_gauge.dart';

/// Le banc d'essai du radar : voir et entendre l'alerte sans radar, sans vélo et
/// sans voiture.
///
/// Elle n'imite rien. Ce sont **les widgets de la sortie** qui sont montés ici —
/// la même jauge, le même cadre, les mêmes mètres — nourris par le même
/// [RadarViewNotifier] et doublés du même lecteur de sons. Une page qui
/// redessinerait le radar à sa façon ne prouverait que sa propre justesse ;
/// celle-ci prouve celle de la sortie.
///
/// Le fond n'est pas décoratif non plus : il passe du blanc au sombre pour que
/// le halo des pastilles et l'ombre des chiffres soient jugés sur le pire cas —
/// une carte enneigée en haut, une forêt en bas.
class RadarDebugPage extends StatefulWidget {
  const RadarDebugPage({super.key});

  @override
  State<RadarDebugPage> createState() => _RadarDebugPageState();
}

class _RadarDebugPageState extends State<RadarDebugPage> {
  /// Les trames simulées, à la place de `SensorHub.latestRadar`. Volontairement
  /// séparées du hub : une trame inventée n'a rien à faire dans le flux d'une
  /// vraie sortie, même de passage.
  final _samples = ValueNotifier<RadarSample?>(null);
  late final RadarViewNotifier _radar;

  final _voice = RadarAlertVoice();
  final _sound = RadarAlertPlayer();

  /// Le temps de la simulation. Un chronomètre plutôt qu'un compteur de tics :
  /// changer la cadence d'affichage ne doit pas changer la vitesse des voitures.
  final _clock = Stopwatch();
  Timer? _timer;

  int _cars = 1;
  double _approachMps = 14;

  /// Cadence de rafraîchissement. Le vrai radar publie autour d'une trame par
  /// seconde ; on va plus vite ici pour juger le mouvement de la jauge, pas pour
  /// tricher — la sévérité, elle, ne dépend que des distances.
  static const _tick = Duration(milliseconds: 250);

  RadarSimulator get _simulator =>
      RadarSimulator(cars: _cars, approachMps: _approachMps);

  bool get _running => _timer != null;

  @override
  void initState() {
    super.initState();
    _radar = RadarViewNotifier(_samples);
    _radar.addListener(_speak);
    unawaited(_sound.warmUp());
  }

  void _speak() {
    if (_voice.read(_radar.value.severity) case final cue?) _sound.play(cue);
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      _timer = null;
      _clock
        ..stop()
        ..reset();
      // Plus de trames du tout, et pas des trames vides : c'est la différence
      // entre « radar débranché » et « route dégagée », et l'occasion de
      // vérifier que l'arrêt ne joue **pas** le son du dégagement.
      _samples.value = null;
    } else {
      _clock.start();
      _timer = Timer.periodic(_tick, (_) => _emit());
      _emit();
    }
    setState(() {});
  }

  void _emit() =>
      _samples.value = _simulator.sampleAt(_clock.elapsed, now: DateTime.now());

  @override
  void dispose() {
    _timer?.cancel();
    _radar.removeListener(_speak);
    _radar.dispose();
    _sound.dispose();
    _samples.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Pas d'`AppBar` : les mètres s'affichent dans la bande de l'encoche, et
      // une barre par-dessus les mettrait ailleurs que là où on veut les juger.
      body: ValueListenableBuilder<RadarView>(
        valueListenable: _radar,
        builder: (context, radar, _) => Stack(
          children: [
            const Positioned.fill(child: _Backdrop()),
            for (final side in RadarGaugeSide.values)
              Positioned(
                left: side == RadarGaugeSide.left ? 0 : null,
                right: side == RadarGaugeSide.right ? 0 : null,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: MapEdgeHandle.width,
                  child: RadarSideGauge(view: radar, side: side),
                ),
              ),
            Positioned.fill(child: RadarFrame(severity: radar.severity)),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: RadarDistanceBadges(view: radar),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Controls(
                radar: radar,
                cars: _cars,
                approachMps: _approachMps,
                running: _running,
                onCars: (cars) {
                  setState(() => _cars = cars);
                  if (_running) _emit();
                },
                onSpeed: (speed) => setState(() => _approachMps = speed),
                onToggle: _toggle,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un fond qui va du clair au sombre, pour juger la lisibilité aux deux bouts.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF2F4F5),
            Color(0xFFC9D6C0),
            Color(0xFF5A6B4E),
            Color(0xFF1B2418),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.radar,
    required this.cars,
    required this.approachMps,
    required this.running,
    required this.onCars,
    required this.onSpeed,
    required this.onToggle,
    required this.onClose,
  });

  final RadarView radar;
  final int cars;
  final double approachMps;
  final bool running;
  final ValueChanged<int> onCars;
  final ValueChanged<double> onSpeed;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xE6101214),
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        // Même leçon qu'ailleurs : l'appli dessine derrière la barre de
        // navigation d'Android, à nous de lui laisser sa place.
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _readout(),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Aucune')),
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
            ],
            selected: {cars},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onCars(selection.first),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.speed, size: 18, color: Colors.white54),
              Expanded(
                child: Slider(
                  value: approachMps,
                  min: 4,
                  max: 30,
                  divisions: 26,
                  label: '${approachMps.round()} m/s',
                  onChanged: onSpeed,
                ),
              ),
              // La vitesse d'approche est un écart, pas une vitesse au sol : la
              // donner aussi en km/h évite de la confondre avec celle de la
              // voiture.
              SizedBox(
                width: 78,
                child: Text(
                  '${approachMps.round()} m/s\n${(approachMps * 3.6).round()} km/h',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onToggle,
                  icon: Icon(running ? Icons.stop : Icons.play_arrow),
                  label: Text(running ? 'Débrancher le radar' : 'Démarrer'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(onPressed: onClose, child: const Text('Fermer')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _readout() {
    final label = switch (radar.severity) {
      RadarSeverity.absent => 'Pas de radar',
      RadarSeverity.clear => 'Voie libre',
      RadarSeverity.approaching => 'Véhicule en approche',
      RadarSeverity.close => 'Véhicule proche',
    };
    final detail = radar.nearestM == null
        ? ''
        : '  ·  ${radar.count} véhicule${radar.count > 1 ? 's' : ''}'
            '  ·  ${radar.nearestM} m';

    return Text(
      '$label$detail',
      style: const TextStyle(color: Colors.white, fontSize: 14),
    );
  }
}
