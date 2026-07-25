import 'package:flutter/material.dart';

/// The entrance easing used across the mockups (`cubic-bezier(0.22,1,0.36,1)`),
/// a soft "ease-out-expo" that decelerates gently into place.
const Cubic kEntranceCurve = Cubic(0.22, 1.0, 0.36, 1.0);

/// A one-shot entrance: the child fades up into place, optionally after a
/// [delay] (used to stagger a list/grid of cells like the design's bento
/// modules). Honors the platform "reduce motion" setting — when animations are
/// disabled it renders the child immediately with no transition.
class EntranceFade extends StatefulWidget {
  const EntranceFade({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 450),
    this.beginOffset = const Offset(0, 0.08),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Starting translation as a fraction of the child's size (slides up by
  /// default). Zero disables the slide, keeping only the fade.
  final Offset beginOffset;

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curved = CurvedAnimation(
    parent: _controller,
    curve: kEntranceCurve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1; // respect reduce-motion: snap to final frame.
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.beginOffset,
          end: Offset.zero,
        ).animate(_curved),
        child: widget.child,
      ),
    );
  }
}
