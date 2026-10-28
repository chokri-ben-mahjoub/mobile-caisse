import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class FloatingNavItem {
  const FloatingNavItem({required this.label, required this.icon, required this.selectedIcon, this.badge = 0});
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Small counter on the icon (e.g. low-stock products); 0 = hidden.
  final int badge;
}

/// Floating pill navigation bar: the selected tab expands into a gradient pill with its label.
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.items, required this.selected, required this.onSelected});
  final List<FloatingNavItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          height: 66,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: pal.card,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: pal.border.withValues(alpha: 0.6)),
            boxShadow: const [BoxShadow(color: Color(0x261E3A8A), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                flex: i == selected ? 3 : 1,
                child: _NavButton(
                  item: items[i],
                  selected: i == selected,
                  onTap: () {
                    if (i != selected) HapticFeedback.selectionClick();
                    onSelected(i);
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});
  final FloatingNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final icon = Icon(selected ? item.selectedIcon : item.icon, size: 24, color: selected ? Colors.white : pal.muted);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            gradient: selected ? kHeroGradient : null,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected ? const [BoxShadow(color: Color(0x552563EB), blurRadius: 12, offset: Offset(0, 4))] : null,
          ),
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Badge(isLabelVisible: item.badge > 0, label: Text('${item.badge}'), child: icon),
              if (selected)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(item.label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
