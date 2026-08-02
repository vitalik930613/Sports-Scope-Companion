import 'package:flutter/material.dart';

/// La carte des pages de données : un titre discret, des lignes lisibles.
///
/// Extraite de `ride_summary_page.dart` telle quelle. Elle sert maintenant à
/// plusieurs blocs, qu'un profil peut poser dans n'importe quel ordre : sans
/// mise en forme commune, deux blocs voisins venus de deux endroits du code
/// n'auraient ni le même fond, ni le même arrondi, ni la même marge — et une
/// page composée à la main aurait l'air cassée.
class BlockCard extends StatelessWidget {
  const BlockCard({super.key, required this.title, required this.lines});

  final String title;
  final List<String> lines;

  /// Le fond des cartes, partagé avec [ZoneBreakdown] : c'est ce qui les fait
  /// lire comme des éléments d'une même page.
  static const background = Color(0xFF1F2226);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }
}
