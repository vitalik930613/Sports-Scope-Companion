import 'package:flutter/material.dart';

import 'block_card.dart';

/// Un bouton d'action générique du tableau de bord : un geste qui agit sur la
/// sortie plutôt qu'une mesure qu'on lit.
///
/// Reprend la mise en forme de [RecordingControl] (`recording_block.dart`) —
/// le bouton plein largeur, la case ronde en compact — sans son état : ici un
/// tap ne fait qu'appeler [onPressed].
class DashboardActionButton extends StatelessWidget {
  const DashboardActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.compact,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback? onPressed;

  /// La largeur à laquelle le bouton large se construit avant mise à
  /// l'échelle. Fixe et non celle de la case : [ScaleToFit] la ramène à la
  /// case réelle.
  static const _fullWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: label,
        child: Material(
          color: const Color(0xFF1F2226),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: Icon(
                icon,
                color: onPressed == null ? Colors.white24 : Colors.white70,
              ),
            ),
          ),
        ),
      );
    }

    return ScaleToFit(
      child: SizedBox(
        width: _fullWidth,
        child: FilledButton.icon(
          // Haut : le doigt vise mal sur une route bosselée.
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}
