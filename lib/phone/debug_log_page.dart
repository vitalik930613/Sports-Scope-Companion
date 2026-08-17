import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debug_log.dart';

/// Le journal de bord, en lecture directe sur le téléphone — pour lire un
/// diagnostic (ex. la dérive de boussole) en sortie, sans connexion à
/// l'ordinateur. Banc d'essai temporaire, comme `GattSniffPage`.
class DebugLogPage extends StatelessWidget {
  const DebugLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal'),
        actions: [
          IconButton(
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copier',
          ),
          IconButton(
            onPressed: DebugLog.instance.clear,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Vider',
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: DebugLog.instance.lines,
        builder: (context, lines, _) {
          if (lines.isEmpty) {
            return const Center(child: Text('Rien pour l’instant.'));
          }
          return ListView.builder(
            // Déjà du plus récent au plus ancien : pas besoin de défiler
            // jusqu'en bas pour voir la dernière ligne pendant la sortie.
            itemCount: lines.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Text(
                lines[index],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          );
        },
      ),
    );
  }

  void _copy(BuildContext context) {
    final text = DebugLog.instance.lines.value.reversed.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Journal copié')),
    );
  }
}
