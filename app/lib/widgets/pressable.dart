import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a tappable surface with a subtle press-in scale — the design's
/// `active:scale-95` micro-interaction. Keeps taps snappy (fast scale-down,
/// gentle release) and leaves layout untouched.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Secondary gesture (entering the library's selection mode, for one). Fires
  /// haptic feedback, since a long-press has no visual "it worked" of its own.
  final VoidCallback? onLongPress;
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _setPressed(false);
              HapticFeedback.selectionClick();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: Duration(milliseconds: _pressed ? 90 : 180),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
