import 'package:flutter/material.dart';

/// Keeps finance screens readable on wide displays while using the full
/// available width on phones and narrow tablets.
class FinanceContentFrame extends StatelessWidget {
  const FinanceContentFrame({
    super.key,
    required this.child,
    this.maxWidth = 1120,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
