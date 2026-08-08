import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/gps_source.dart';
import '../../recording/ride_recorder.dart';
import 'block_card.dart';

/// Piloter l'enregistrement sans quitter la sortie : démarrer, suspendre,
/// reprendre.
///
/// Il n'y avait rien : l'enregistrement se décidait au départ, dans la boîte de
/// dialogue de l'écran des capteurs, et refuser était sans retour. Or c'est
/// exactement ici qu'on s'en aperçoit — les pages de données sont vides tant que
/// rien n'est enregistré, et c'est ce vide qui rappelle qu'on a dit non.
///
/// **Toujours rien pour arrêter.** Une pause ne perd rien — le fichier reste
/// ouvert, la sortie repart d'un tap — alors qu'un arrêt clôt la sortie. Un
/// bouton qui termine, à portée de pouce sur une page qu'on consulte en roulant,
/// coûterait un jour une sortie entière ; on termine au retour, depuis l'écran
/// des capteurs.
class RecordingControl extends StatelessWidget {
  const RecordingControl({
    super.key,
    required this.recorder,
    this.mode = RecordingMode.full,
  });

  final RideRecorder recorder;
  final RecordingMode mode;

  @override
  Widget build(BuildContext context) {
    final compact = mode == RecordingMode.compact;

    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) => switch (recorder.state) {
        RecorderState.idle => _StartRecordingButton(
          recorder: recorder,
          compact: compact,
        ),
        RecorderState.recording => _PauseButton(
          recorder: recorder,
          compact: compact,
        ),
        // La pause **garde sa bande orange même en compact**, et c'est le
        // seul mode qui ne se réduit pas : c'est la seule façon de perdre la
        // fin d'une sortie sans s'en apercevoir, donc la seule chose de
        // cette page qui doive crier. Elle perd sa phrase d'explication dans
        // une petite case, jamais son aplat.
        RecorderState.paused => _ResumeBanner(recorder: recorder),
      },
    );
  }
}

/// Le bouton de départ, et son attente.
///
/// À part parce qu'il a un état : `start()` prend le temps d'obtenir une
/// position, et sans ce verrou un pouce impatient sur une piste cyclable en
/// lancerait trois.
class _StartRecordingButton extends StatefulWidget {
  const _StartRecordingButton({required this.recorder, this.compact = false});

  final RideRecorder recorder;
  final bool compact;

  @override
  State<_StartRecordingButton> createState() => _StartRecordingButtonState();
}

class _StartRecordingButtonState extends State<_StartRecordingButton> {
  bool _starting = false;

  Future<void> _start() async {
    // Le messager est pris avant l'attente : après, le `context` peut avoir
    // disparu si le cycliste a changé de page entre-temps.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _starting = true);
    try {
      await widget.recorder.start();
    } on GpsUnavailable catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Enregistrement impossible : $e')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _starting
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.fiber_manual_record, color: Colors.red);

    // « Recherche du GPS… » n'est pas une politesse : `start()` attend une vraie
    // position, ce qui peut durer plusieurs secondes sous les arbres. Sans GPS
    // (profil home-trainer), l'attente n'existe pas et le libellé ne paraît
    // jamais.
    final label = _starting
        ? 'Recherche du GPS…'
        : 'Démarrer l\'enregistrement';

    if (widget.compact) {
      return _CompactButton(
        onPressed: _starting ? null : _start,
        icon: icon,
        tooltip: label,
      );
    }

    return _cardButton(
      naturalWidth: _fullWidth,
      child: FilledButton.icon(
        // Haut : le doigt vise mal sur une route bosselée, et cette page se
        // consulte à l'arrêt ou au feu rouge.
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: _starting ? null : _start,
        icon: icon,
        label: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

/// La largeur à laquelle le bouton large se construit avant mise à l'échelle —
/// ce qu'il faut à « Démarrer l'enregistrement » pour tenir sur une ligne.
/// Plancher et non largeur fixe : sur une case plus large (une ligne de
/// grille pleine largeur), [_stretchToFit] l'étire jusqu'à la case réelle au
/// lieu de le laisser centré, minuscule, au milieu du vide.
const _fullWidth = 200.0;

/// Étire [child] jusqu'à la largeur offerte quand elle dépasse
/// [naturalWidth], au lieu de le laisser centré par [ScaleToFit] au milieu
/// d'une case trop généreuse pour sa taille naturelle. En dessous de
/// [naturalWidth], le comportement ne change pas : [ScaleToFit] réduit
/// toujours le bouton en entier plutôt que de tronquer son libellé.
Widget _stretchToFit({required double naturalWidth, required Widget child}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final width =
          constraints.hasBoundedWidth && constraints.maxWidth > naturalWidth
          ? constraints.maxWidth
          : naturalWidth;
      return ScaleToFit(
        child: SizedBox(width: width, child: child),
      );
    },
  );
}

/// [_stretchToFit], avec en plus le fond anthracite des cartes de mesure —
/// sans lui, le bouton étiré flottait seul sur le noir de la coquille et
/// détonnait à côté des cartes voisines. `_ResumeBanner` ne s'en sert pas :
/// son aplat orange est déjà un fond, et délibérément pas celui-ci.
Widget _cardButton({required double naturalWidth, required Widget child}) {
  return _stretchToFit(
    naturalWidth: naturalWidth,
    child: Container(
      padding: EdgeInsets.all(BlockMetrics.natural.padding),
      decoration: BoxDecoration(
        color: BlockCard.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    ),
  );
}

/// Suspendre l'enregistrement : discret, et sans confirmation.
///
/// Discret parce qu'on ne le cherche qu'en connaissance de cause — un café, une
/// crevaison — et qu'un aplat de plus en haut de page attirerait le pouce pour
/// rien. Sans confirmation parce qu'une pause ne coûte rien : elle se défait
/// d'un tap, et le bandeau du bas fige son chronomètre, ce qui se voit.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.recorder, this.compact = false});

  final RideRecorder recorder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _CompactButton(
        onPressed: recorder.pause,
        icon: const Icon(Icons.pause, color: Colors.white70),
        tooltip: 'Mettre en pause',
      );
    }

    return _cardButton(
      naturalWidth: _fullWidth,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: recorder.pause,
        icon: const Icon(Icons.pause),
        label: const Text('Mettre en pause', style: TextStyle(fontSize: 15)),
      ),
    );
  }
}

/// Reprendre — et surtout **dire qu'on est en pause**.
///
/// C'est la seule façon de perdre la fin d'une sortie sans s'en apercevoir : les
/// compteurs figés se lisent aussi bien comme « en pause » que comme « à
/// l'arrêt à un feu ». D'où l'aplat orange sur toute la largeur, qui ne laisse
/// aucun doute et qui est en même temps le bouton de reprise.
class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.recorder});

  final RideRecorder recorder;

  /// La largeur à laquelle la bande se construit avant mise à l'échelle.
  /// Plancher et non largeur fixe : [_stretchToFit] l'étire jusqu'à la case
  /// réelle quand elle est plus large — c'est ce qui fait « l'aplat orange
  /// sur toute la largeur » du commentaire de classe — et sous ce plancher,
  /// [ScaleToFit] réduit la bande, la phrase d'explication restant toujours
  /// écrite plutôt que retirée.
  static const _naturalWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;

    return _stretchToFit(
      naturalWidth: _naturalWidth,
      child: Material(
        color: const Color(0xFFB35300),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: recorder.resume,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.padding,
              vertical: metrics.padding - 2,
            ),
            child: Row(
              children: [
                const Icon(Icons.pause_circle, color: Colors.white),
                SizedBox(width: metrics.gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Enregistrement en pause',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: metrics.lineSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Rien n\'est écrit — la trace reprend où elle s\'est arrêtée.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: metrics.titleSize - 1,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: metrics.gap),
                const Icon(Icons.play_arrow, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La variante d'une cellule de grille : l'icône seule, mais sur toute la
/// cellule. La cible tactile est donc plus grande qu'en mode large, ce qui est
/// exactement ce qu'il faut à vélo — on vise mal.
class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF1F2226),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(child: icon),
        ),
      ),
    );
  }
}
