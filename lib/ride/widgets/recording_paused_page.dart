import 'package:flutter/material.dart';

/// Le rappel affiché tant que l'enregistrement est en pause — la seule façon
/// de perdre la fin d'une sortie sans s'en apercevoir, les compteurs figés se
/// lisant aussi bien comme « en pause » que comme « à l'arrêt à un feu » (voir
/// `_ResumeBanner`, `blocks/recording_block.dart`, qui dit la même chose mais
/// seulement sur la page qui porte le bloc d'enregistrement). Par-dessus
/// toute la sortie — carte et pages de données comprises — pour qu'il n'y ait
/// plus besoin d'être sur cette page-là pour s'en apercevoir.
///
/// Un pictogramme en transparence, pas un voile : ni fond opaque ni tap qui
/// capte le geste — la carte et les pages restent utilisables sous la pause,
/// et seul un bouton dédié (`_ResumeBanner`, `TogglePauseControl`) reprend
/// l'enregistrement, jamais un tap sur ce rappel.
class RecordingPausedPage extends StatelessWidget {
  const RecordingPausedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Icon(
          Icons.pause_circle,
          color: Colors.white.withValues(alpha: 0.35),
          size: 120,
        ),
      ),
    );
  }
}
