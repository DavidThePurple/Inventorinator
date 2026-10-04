import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class GettingStartedTourStep {
  const GettingStartedTourStep({
    required this.target,
    required this.section,
    required this.title,
    required this.body,
  });

  final GlobalKey target;
  final String section;
  final String title;
  final String body;
}

class OnboardingReplayNudge extends StatefulWidget {
  const OnboardingReplayNudge({super.key, required this.onExpired});

  final VoidCallback onExpired;

  @override
  State<OnboardingReplayNudge> createState() => _OnboardingReplayNudgeState();
}

class _OnboardingReplayNudgeState extends State<OnboardingReplayNudge> {
  Timer? _dismissTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    _dismissTimer = Timer(const Duration(seconds: 7), _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    setState(() => _visible = false);
    Future<void>.delayed(const Duration(milliseconds: 220), widget.onExpired);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Positioned(
      right: 20,
      bottom: math.max(108, height * .30),
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(1.08, 0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 12,
            shadowColor: Theme.of(context).colorScheme.primary
                .withValues(alpha: .22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 292,
              height: 72,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 19,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'You can restart the onboarding playthrough in the Personalization view.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GettingStartedTour extends StatefulWidget {
  const GettingStartedTour({
    super.key,
    required this.steps,
    required this.initialStep,
    required this.onStepChanged,
    required this.onDone,
  });

  final List<GettingStartedTourStep> steps;
  final int initialStep;
  final ValueChanged<int> onStepChanged;
  final VoidCallback onDone;

  @override
  State<GettingStartedTour> createState() => _GettingStartedTourState();
}

class _GettingStartedTourState extends State<GettingStartedTour>
    with SingleTickerProviderStateMixin {
  late int _step = widget.initialStep.clamp(0, widget.steps.length - 1);
  Rect? _targetRect;
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTarget());
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _measureTarget() {
    final renderObject = widget.steps[_step].target.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize || !mounted) {
      setState(() => _targetRect = null);
      return;
    }
    setState(
      () => _targetRect =
          renderObject.localToGlobal(Offset.zero) & renderObject.size,
    );
  }

  void _goTo(int next) {
    setState(() {
      _step = next.clamp(0, widget.steps.length - 1);
      _targetRect = null;
    });
    widget.onStepChanged(_step);
    _entranceController.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTarget());
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_step];
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final target = _targetRect;
          const sideMargin = 20.0;
          final cardWidth = math.min(460.0, size.width - (sideMargin * 2));
          const cardHeight = 220.0;
          final targetCenter = target?.center.dx ?? size.width / 2;
          final left = (targetCenter - cardWidth / 2).clamp(
            sideMargin,
            size.width - cardWidth - sideMargin,
          );
          final roomBelow = target == null ? 0.0 : size.height - target.bottom;
          final preferredTop = target == null
              ? (size.height - cardHeight) / 2
              : roomBelow >= cardHeight + 32
              ? target.bottom + 24
              : math.max(sideMargin, target.top - cardHeight - 24);
          final top = preferredTop.clamp(
            sideMargin,
            size.height - cardHeight - sideMargin,
          );
          final cardAboveTarget = target != null && top < target.top;
          return Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _entranceController,
                      builder: (context, _) => CustomPaint(
                        painter: _TourSpotlightPainter(
                          target: target,
                          colorScheme: Theme.of(context).colorScheme,
                          entrance: Curves.easeOutCubic.transform(
                            _entranceController.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (target != null)
                AnimatedPositioned(
                  left: targetCenter - 13,
                  top: cardAboveTarget ? top + cardHeight - 7 : top - 17,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    cardAboveTarget
                        ? Icons.arrow_drop_down_rounded
                        : Icons.arrow_drop_up_rounded,
                    size: 28,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              AnimatedPositioned(
                left: left,
                top: top,
                width: cardWidth,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Semantics(
                  label: 'Getting started: ${step.title}',
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _entranceController,
                      curve: const Interval(.08, 1, curve: Curves.easeOut),
                    ),
                    child: ScaleTransition(
                      scale: Tween<double>(begin: .975, end: 1).animate(
                        CurvedAnimation(
                          parent: _entranceController,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .32),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      step.section,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.05,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '${_step + 1} of ${widget.steps.length}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                step.title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 7),
                              Text(step.body),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (_step > 0)
                                    IconButton(
                                      key: const Key('getting-started-back'),
                                      tooltip: 'Back',
                                      onPressed: () => _goTo(_step - 1),
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                      ),
                                    ),
                                  TextButton(
                                    key: const Key('getting-started-skip'),
                                    onPressed: widget.onDone,
                                    child: const Text('Skip'),
                                  ),
                                  const SizedBox(width: 6),
                                  FilledButton(
                                    key: const Key('getting-started-next'),
                                    onPressed: _step == widget.steps.length - 1
                                        ? widget.onDone
                                        : () => _goTo(_step + 1),
                                    child: Text(
                                      _step == widget.steps.length - 1
                                          ? 'Done'
                                          : 'Next',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TourSpotlightPainter extends CustomPainter {
  const _TourSpotlightPainter({
    required this.target,
    required this.colorScheme,
    required this.entrance,
  });

  final Rect? target;
  final ColorScheme colorScheme;
  final double entrance;

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreen = Path()..addRect(Offset.zero & size);
    if (target == null) {
      canvas.drawPath(
        fullScreen,
        Paint()..color = Colors.black.withValues(alpha: .62),
      );
      return;
    }
    final spotlight = RRect.fromRectAndRadius(
      target!.inflate(8),
      const Radius.circular(16),
    );
    final cutout = Path()..addRRect(spotlight);
    canvas.drawPath(
      Path.combine(PathOperation.difference, fullScreen, cutout),
      Paint()..color = Colors.black.withValues(alpha: .62),
    );
    canvas.drawRRect(
      spotlight,
      Paint()
        ..color = colorScheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + (1 - entrance) * 1.5,
    );
    if (entrance < .92) {
      final echo = RRect.fromRectAndRadius(
        target!.inflate(8 + (1 - entrance) * 18),
        const Radius.circular(20),
      );
      canvas.drawRRect(
        echo,
        Paint()
          ..color = colorScheme.primary.withValues(alpha: (1 - entrance) * .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TourSpotlightPainter oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.entrance != entrance;
}
