import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../logic/sales_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';

/// "Objectif du jour": animated ring with today's sales vs the daily target.
/// Tap to change the target; a small celebration plays when it is reached.
class DailyGoalCard extends StatefulWidget {
  const DailyGoalCard({super.key, this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 0)});

  final EdgeInsets padding;

  @override
  State<DailyGoalCard> createState() => _DailyGoalCardState();
}

class _DailyGoalCardState extends State<DailyGoalCard> {
  bool _wasReached = false;
  bool _primed = false;

  Future<void> _edit(double current) async {
    final c = TextEditingController(text: current > 0 ? current.toStringAsFixed(0) : '');
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Objectif du jour'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'Ex. 500', helperText: '0 pour désactiver'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.')) ?? 0),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (v == null || !mounted) return;
    final sp = context.read<SettingsProvider>();
    await sp.update(sp.settings.copyWith(dailyGoal: v < 0 ? 0 : v));
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final settings = context.watch<SettingsProvider>().settings;
    final sales = context.watch<SalesProvider>();
    final goal = settings.dailyGoal;
    if (goal <= 0) return const SizedBox.shrink();

    final today = sales.isToday ? sales.total : 0.0;
    final ratio = (today / goal).clamp(0.0, 1.0);
    final reached = today >= goal;
    // Celebrate only on the transition, not when the app opens already above target.
    if (_primed && reached && !_wasReached) HapticFeedback.heavyImpact();
    _primed = true;
    _wasReached = reached;

    final left = math.max(0.0, goal - today);
    final color = reached ? const Color(0xFF12A150) : kBlue;

    return Padding(
      padding: widget.padding,
      child: Material(
        color: pal.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _edit(goal),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: pal.shadow),
            child: Row(children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: ratio),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: v,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: color.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    reached
                        ? Icon(Icons.emoji_events_rounded, color: color, size: 24)
                        : Text('${(v * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: color)),
                  ]),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(reached ? 'Objectif atteint ! 🎉' : 'Objectif du jour',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    reached
                        ? '${settings.money(today)} · +${settings.money(today - goal)} au-dessus'
                        : '${settings.money(today)} / ${settings.money(goal)} · encore ${settings.money(left)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ]),
              ),
              Icon(Icons.edit_rounded, size: 16, color: pal.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
