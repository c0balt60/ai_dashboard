import 'package:flutter/material.dart';

import 'status_visuals.dart';

/// Small colored dot; pulses when [visual] is animated.
class StatusDot extends StatefulWidget {
  const StatusDot(this.visual, {super.key, this.size = 10});

  final StatusVisual visual;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.visual.animated) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.visual.color;
    return SizedBox.square(
      dimension: widget.size * 1.8,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.visual.animated)
              Container(
                width: widget.size * (1 + 0.8 * _controller.value),
                height: widget.size * (1 + 0.8 * _controller.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(
                    alpha: 0.35 * (1 - _controller.value),
                  ),
                ),
              ),
            child!,
          ],
        ),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}
