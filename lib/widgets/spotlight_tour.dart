import 'package:flutter/material.dart';

class SpotlightStep {
  final String title;
  final String description;
  final GlobalKey? targetKey;
  final int tabIndex;
  final EdgeInsets cutoutPadding;
  final double borderRadius;
  final Widget? contentWidget;

  const SpotlightStep({
    required this.title,
    required this.description,
    this.targetKey,
    this.tabIndex = 0,
    this.cutoutPadding = const EdgeInsets.all(10),
    this.borderRadius = 18.0,
    this.contentWidget,
  });
}

class SpotlightOverlay extends StatefulWidget {
  final List<SpotlightStep> steps;
  final int currentStepIndex;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;
  final VoidCallback onFinish;

  const SpotlightOverlay({
    super.key,
    required this.steps,
    required this.currentStepIndex,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
    required this.onFinish,
  });

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<SpotlightOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Entry Fade & Scale Animation (200ms)
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Subtle Cutout Glow Pulse Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 2.0, end: 3.5).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _animController.forward();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Device rotation / window resize -> Force re-measure target bounds
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant SpotlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStepIndex != widget.currentStepIndex) {
      _animController.reset();
      _animController.forward();
      // Re-trigger measurement after frame completes (essential for tab transitions)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Robust target bounds calculation with off-screen fallback
  Rect? _getTargetRect(GlobalKey? key, Size screenSize) {
    if (key == null || key.currentContext == null) return null;
    final renderBox = key.currentContext!.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return null;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final rect = offset & size;

    // Fallback Check: If rect is empty or completely off-screen, fall back to centered modal (return null)
    if (rect.isEmpty ||
        rect.width <= 0 ||
        rect.height <= 0 ||
        rect.left >= screenSize.width ||
        rect.top >= screenSize.height ||
        rect.right <= 0 ||
        rect.bottom <= 0) {
      return null;
    }

    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[widget.currentStepIndex];
    final isFirst = widget.currentStepIndex == 0;
    final isLast = widget.currentStepIndex == widget.steps.length - 1;
    final screenSize = MediaQuery.of(context).size;

    // Robust cutout rect with screen bounds check
    final targetRect = _getTargetRect(step.targetKey, screenSize);

    Rect? cutoutRect;
    if (targetRect != null) {
      cutoutRect = Rect.fromLTRB(
        (targetRect.left - step.cutoutPadding.left).clamp(0, screenSize.width),
        (targetRect.top - step.cutoutPadding.top).clamp(0, screenSize.height),
        (targetRect.right + step.cutoutPadding.right).clamp(0, screenSize.width),
        (targetRect.bottom + step.cutoutPadding.bottom).clamp(0, screenSize.height),
      );
    }

    final isLandscape = screenSize.width > screenSize.height && screenSize.height < 600;

    // Auto-flip tooltip placement (above or below cutout) with small screen clamping
    bool placeAbove = false;
    if (cutoutRect != null) {
      final spaceBelow = screenSize.height - cutoutRect.bottom;
      placeAbove = spaceBelow < 210 && cutoutRect.top > 210;
    }

    final double topPos = cutoutRect == null
        ? (screenSize.height / 2 - (isLandscape ? 110 : 140)).clamp(12.0, (screenSize.height - 240.0).clamp(12.0, screenSize.height))
        : (placeAbove
            ? (cutoutRect.top - (isLandscape ? 190 : 230)).clamp(12.0, (screenSize.height - 240.0).clamp(12.0, screenSize.height))
            : (cutoutRect.bottom + 12).clamp(12.0, (screenSize.height - 240.0).clamp(12.0, screenSize.height)));

    final double horizMargin = isLandscape ? 60.0 : 20.0;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Stack(
        children: [
          // 1. Dark Overlay with Glowing Pulse Spotlight Cutout
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: _SpotlightPainter(
                    cutoutRect: cutoutRect,
                    borderRadius: step.borderRadius,
                    pulseWidth: _pulseAnimation.value,
                  ),
                );
              },
            ),
          ),

          // 2. Opaque gesture barrier to prevent background interactions
          Positioned.fill(
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),

          // 3. Floating Tooltip Card with Scale + Fade Transition & Accessibility
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            left: horizMargin,
            right: horizMargin,
            top: topPos,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Semantics(
                label:
                    'Step ${widget.currentStepIndex + 1} of ${widget.steps.length}: ${step.title}. ${step.description}',
                container: true,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: isLandscape ? screenSize.height * 0.82 : screenSize.height * 0.85,
                    ),
                    padding: EdgeInsets.all(isLandscape ? 14 : 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFF6366F1),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: isLandscape
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left Side: Step Info & Description & Sample Card
                              Expanded(
                                flex: 3,
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1)
                                              .withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'STEP ${widget.currentStepIndex + 1} OF ${widget.steps.length}',
                                          style: const TextStyle(
                                            color: Color(0xFF818CF8),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        step.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        step.description,
                                        style: const TextStyle(
                                          color: Color(0xFFCDD6F4),
                                          fontSize: 12,
                                          height: 1.35,
                                        ),
                                      ),
                                      if (step.contentWidget != null) ...[
                                        const SizedBox(height: 8),
                                        step.contentWidget!,
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 160,
                                margin: const EdgeInsets.symmetric(horizontal: 14),
                                color: const Color(0xFF313244),
                              ),
                              // Right Side: Vertical Action Controls
                              Expanded(
                                flex: 2,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FilledButton.icon(
                                      onPressed:
                                          isLast ? widget.onFinish : widget.onNext,
                                      icon: Icon(
                                        isLast
                                            ? Icons.check_circle
                                            : Icons.arrow_forward,
                                        size: 16,
                                      ),
                                      label: Text(isLast ? 'Got it!' : 'Next'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF6366F1),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(48, 48),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 10),
                                      ),
                                    ),
                                    if (!isFirst) ...[
                                      const SizedBox(height: 8),
                                      OutlinedButton.icon(
                                        onPressed: widget.onBack,
                                        icon: const Icon(Icons.arrow_back, size: 16),
                                        label: const Text('Back'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: const BorderSide(
                                              color: Color(0xFF45475A)),
                                          minimumSize: const Size(48, 48),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 10),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    TextButton(
                                      onPressed: widget.onSkip,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.grey[400],
                                        minimumSize: const Size(48, 44),
                                      ),
                                      child: const Text('Skip Tour',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Step Counter Header Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1)
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'STEP ${widget.currentStepIndex + 1} OF ${widget.steps.length}',
                                        style: const TextStyle(
                                          color: Color(0xFF818CF8),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: widget.onSkip,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.grey[400],
                                        minimumSize: const Size(48, 48), // 48dp Touch Target
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('Skip Tour',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Step Title
                                Text(
                                  step.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Step Description
                                Text(
                                  step.description,
                                  style: const TextStyle(
                                    color: Color(0xFFCDD6F4),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),

                                // Inline Content Widget (e.g. Widget Sample Card)
                                if (step.contentWidget != null) ...[
                                  const SizedBox(height: 10),
                                  step.contentWidget!,
                                ],

                                const SizedBox(height: 18),

                                // Action Buttons (48dp Minimum Touch Target Size)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (!isFirst)
                                      OutlinedButton.icon(
                                        onPressed: widget.onBack,
                                        icon: const Icon(Icons.arrow_back, size: 16),
                                        label: const Text('Back'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: const BorderSide(color: Color(0xFF45475A)),
                                          minimumSize: const Size(48, 48), // 48dp Touch Target
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                        ),
                                      )
                                    else
                                      const SizedBox.shrink(),
                                    FilledButton.icon(
                                      onPressed: isLast ? widget.onFinish : widget.onNext,
                                      icon: Icon(
                                        isLast ? Icons.check_circle : Icons.arrow_forward,
                                        size: 16,
                                      ),
                                      label: Text(isLast ? 'Got it!' : 'Next'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF6366F1),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(48, 48), // 48dp Touch Target
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 12),
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
    ),
  );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? cutoutRect;
  final double borderRadius;
  final double pulseWidth;

  _SpotlightPainter({
    required this.cutoutRect,
    required this.borderRadius,
    required this.pulseWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = const Color(0xCC0F172A); // Translucent Dark Slate Backdrop

    final outerPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (cutoutRect == null) {
      canvas.drawPath(outerPath, backgroundPaint);
      return;
    }

    final innerPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(cutoutRect!, Radius.circular(borderRadius)),
      );

    // Combine paths to create spotlight cutout hole
    final combinedPath = Path.combine(
      PathOperation.difference,
      outerPath,
      innerPath,
    );

    canvas.drawPath(combinedPath, backgroundPaint);

    // Draw gently pulsing glowing border around cutout
    final borderPaint = Paint()
      ..color = Color.lerp(
        const Color(0xFF6366F1),
        const Color(0xFF818CF8),
        (pulseWidth - 2.0) / 1.5,
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = pulseWidth;

    canvas.drawRRect(
      RRect.fromRectAndRadius(cutoutRect!, Radius.circular(borderRadius)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.cutoutRect != cutoutRect ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.pulseWidth != pulseWidth;
  }
}
