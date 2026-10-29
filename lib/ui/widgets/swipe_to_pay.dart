import 'package:flutter/material.dart' hide Text;

import '../i18n/text.dart';

import 'package:flutter/services.dart';

import '../theme.dart';

/// "Glisser pour encaisser": drag the thumb to the end to confirm.
/// Disabled (greyed) when [onConfirm] is null.
class SwipeToPay extends StatefulWidget {
  const SwipeToPay({
    super.key,
    required this.label,
    this.trailing,
    this.onConfirm,
    this.height = 60,
  });

  final double height;

  final String label;
  final String? trailing;
  final VoidCallback? onConfirm;

  @override
  State<SwipeToPay> createState() => _SwipeToPayState();
}

class _SwipeToPayState extends State<SwipeToPay>
    with SingleTickerProviderStateMixin {
  double get _h => widget.height;
  static const _pad = 5.0;
  double _x = 0; // thumb offset, 0..max
  late final AnimationController _back =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
      )..addListener(
        () => setState(
          () => _x = _from * (1 - Curves.easeOut.transform(_back.value)),
        ),
      );
  double _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _release() {
    _from = _x;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onConfirm != null;
    return LayoutBuilder(
      builder: (ctx, c) {
        final max = c.maxWidth - _h + _pad * 2 - _pad * 2;
        final progress = max <= 0 ? 0.0 : (_x / max).clamp(0.0, 1.0);
        // The slider always goes left to right, whatever the language.
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            height: _h,
            decoration: BoxDecoration(
              gradient: enabled ? kHeroGradient : null,
              color: enabled ? null : ctx.pal.soft2,
              borderRadius: BorderRadius.circular(_h / 2),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(left: _h, right: 14),
                    child: Center(
                      child: Opacity(
                        opacity: (1 - progress * 1.6).clamp(0.0, 1.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            enabled
                                ? '${widget.label}${widget.trailing == null ? '' : ' · ${widget.trailing}'}  ›››'
                                : widget.label,
                            maxLines: 1,
                            style: TextStyle(
                              color: enabled ? Colors.white : ctx.pal.muted,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: _pad + _x,
                  child: GestureDetector(
                    onHorizontalDragUpdate: enabled
                        ? (d) {
                            _back.stop();
                            setState(
                              () => _x = (_x + d.delta.dx).clamp(0.0, max),
                            );
                          }
                        : null,
                    onHorizontalDragEnd: enabled
                        ? (_) {
                            if (_x >= max * 0.85) {
                              HapticFeedback.mediumImpact();
                              widget.onConfirm!();
                            }
                            _release();
                          }
                        : null,
                    child: Container(
                      width: _h - _pad * 2,
                      height: _h - _pad * 2,
                      decoration: BoxDecoration(
                        color: enabled ? Colors.white : ctx.pal.card,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 32,
                        color: enabled ? kBlue : ctx.pal.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
