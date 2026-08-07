import 'package:flutter/material.dart';

import 'climb_debug_data.dart';
import 'climb_profile.dart';
import 'nav_state.dart';
import 'widgets/climb_badge.dart';
import 'widgets/climb_profile_overlay.dart';

/// Le banc d'essai du col : voir la pastille et le graphique gradué sans
/// grimper un col réel.
///
/// Comme `RadarDebugPage`, ce sont **les widgets de la sortie** qui sont
/// montés ici — [ClimbBadge] et [ClimbProfileOverlay] tels quels — nourris
/// d'un profil synthétique (même forme que `buildDebugClimb` côté site :
/// segments colorés de 3 % à 14 %, curseur déplaçable).
class ClimbDebugPage extends StatefulWidget {
  const ClimbDebugPage({super.key});

  @override
  State<ClimbDebugPage> createState() => _ClimbDebugPageState();
}

class _ClimbDebugPageState extends State<ClimbDebugPage> {
  late final ClimbProfile _profile = debugClimbProfile();

  double _ratio = 0.42;
  bool _expanded = false;

  NavClimb get _climb => debugClimbFor(_profile, _ratio);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: _Backdrop()),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              bottom: false,
              child: _expanded
                  ? const SizedBox.shrink()
                  : ClimbBadge(
                      climb: _climb,
                      onTap: () => setState(() => _expanded = true),
                    ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 220,
            child: _expanded
                ? ClimbProfileOverlay(
                    climb: _climb,
                    profile: _profile,
                    onTap: () => setState(() => _expanded = false),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Controls(
              ratio: _ratio,
              expanded: _expanded,
              onRatio: (v) => setState(() => _ratio = v),
              onExpanded: (v) => setState(() => _expanded = v),
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2F4F5), Color(0xFFC9D6C0), Color(0xFF5A6B4E)],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.ratio,
    required this.expanded,
    required this.onRatio,
    required this.onExpanded,
    required this.onClose,
  });

  final double ratio;
  final bool expanded;
  final ValueChanged<double> onRatio;
  final ValueChanged<bool> onExpanded;
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
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.landscape, size: 18, color: Colors.white54),
              Expanded(
                child: Slider(
                  value: ratio,
                  onChanged: onRatio,
                  label: '${(ratio * 100).round()} %',
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(ratio * 100).round()} %',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onExpanded(!expanded),
                  icon: Icon(expanded ? Icons.unfold_less : Icons.unfold_more),
                  label: Text(expanded ? 'Replier' : 'Déplier'),
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
}
