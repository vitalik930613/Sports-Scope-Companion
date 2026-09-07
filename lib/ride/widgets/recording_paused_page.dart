import 'package:flutter/material.dart';

/// L'aplat plein écran affiché tant que l'enregistrement est en pause — la
/// seule façon de perdre la fin d'une sortie sans s'en apercevoir, les
/// compteurs figés se lisant aussi bien comme « en pause » que comme « à
/// l'arrêt à un feu » (voir `_ResumeBanner`, `blocks/recording_block.dart`,
/// affichée elle sur la seule page qui porte le bloc d'enregistrement). Ici,
/// par-dessus toute la sortie — carte et pages de données comprises — pour
/// qu'il n'y ait plus besoin d'être sur cette page-là pour s'en apercevoir.
///
/// Même orange, mêmes textes, et même geste — tap n'importe où pour
/// reprendre — que `_ResumeBanner` : deux habillages du même état, jamais
/// deux messages différents.
class RecordingPausedPage extends StatelessWidget {
  const RecordingPausedPage({super.key, required this.onResume});

  final VoidCallback onResume;

  static const _paused = Color(0xFFB35300);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onResume,
      child: ColoredBox(
        color: _paused,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pause_circle, color: Colors.white, size: 72),
                  const SizedBox(height: 20),
                  const Text(
                    'Enregistrement en pause',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 26,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rien n\'est écrit — la trace reprend où elle s\'est arrêtée.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Toucher l\'écran pour reprendre',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
