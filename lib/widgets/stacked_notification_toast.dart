import 'package:flutter/material.dart';

class ToastNotification {
  final String id;
  final String message;
  final Color backgroundColor;

  ToastNotification({
    required this.id,
    required this.message,
    required this.backgroundColor,
  });
}

class StackedNotificationToast extends StatefulWidget {
  final Widget child;
  final int maxStacked;

  const StackedNotificationToast({
    super.key,
    required this.child,
    this.maxStacked = 3,
  });

  static StackedNotificationToastState? of(BuildContext context) {
    return context.findAncestorStateOfType<StackedNotificationToastState>();
  }

  @override
  StackedNotificationToastState createState() => StackedNotificationToastState();
}

class StackedNotificationToastState extends State<StackedNotificationToast> {
  final List<ToastNotification> _notifications = [];

  void showNotification(String message, Color backgroundColor) {
    final notification = ToastNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      message: message,
      backgroundColor: backgroundColor,
    );

    setState(() {
      _notifications.add(notification);
      if (_notifications.length > widget.maxStacked) {
        _notifications.removeAt(0);
      }
    });

    // Staggered disappearance timer: 3.5s base for each notification
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() {
          _notifications.removeWhere((n) => n.id == notification.id);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          widget.child,
          // Positioned at the TOP of the application screen
          Positioned(
            top: 10,
            left: 20,
            right: 20,
            child: SafeArea(
              child: IgnorePointer(
                child: SizedBox(
                  height: 160,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.none,
                    children: List.generate(_notifications.length, (index) {
                      final n = _notifications[index];
                      // Reverse depth index: newest (last in list) is depth 0 (front)
                      final depth = _notifications.length - 1 - index;

                      final scale = 1.0 - (depth * 0.05);
                      final topOffset = depth * 14.0;
                      final opacity = 1.0 - (depth * 0.2);

                      return AnimatedPositioned(
                        key: ValueKey(n.id),
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutBack,
                        top: topOffset,
                        left: 0,
                        right: 0,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutBack,
                          scale: scale.clamp(0.85, 1.0),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: opacity.clamp(0.3, 1.0),
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: n.backgroundColor,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      n.backgroundColor == Colors.green
                                          ? Icons.check_circle
                                          : n.backgroundColor == Colors.orange
                                              ? Icons.warning_rounded
                                              : Icons.info_outline,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        n.message,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
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
