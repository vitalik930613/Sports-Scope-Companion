import 'package:flutter/material.dart';

/// Boîte de choix du fond de carte de navigation.
///
/// Partagée entre les deux endroits où on peut le changer — `CompanionSettingsPage`
/// (avant de partir, écrit le compte par `MapStyleWrite`) et le menu d'une page de
/// sortie (`RideShellPage`, en roulant, écrit la page en direct par
/// `NavigationWebController.setMapStyle`) — pour que ce soit la même boîte plutôt
/// que deux qui divergent avec le temps. Ce qu'on fait du choix reste au
/// responsabilité de l'appelant, cette boîte ne fait que le recueillir.
Future<String?> pickMapStyle(
  BuildContext context, {
  required List<({String id, String label})> styles,
  required String? current,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Fond de carte de navigation'),
      children: [
        RadioGroup<String>(
          groupValue: current,
          onChanged: (id) => Navigator.of(context).pop(id),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in styles)
                RadioListTile<String>(value: style.id, title: Text(style.label)),
            ],
          ),
        ),
      ],
    ),
  );
}
