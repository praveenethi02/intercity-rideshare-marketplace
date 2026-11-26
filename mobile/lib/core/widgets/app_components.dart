import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Small coloured label for a status, such as "Approved" or "In review".
/// Each feature maps its own status codes to a [StatusTone].
class AppBadge extends StatelessWidget {
  final String label;
  final StatusTone tone;
  final IconData? icon;
  const AppBadge(this.label, {super.key, this.tone = StatusTone.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = AppStatusColors.of(context, tone);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w600,
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: colors.foreground),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(label, style: style),
      ]),
    );
  }
}

/// A white card with the design system's border and corners. Tappable when [onTap] is set.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(AppSpacing.lg)});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// A grey placeholder block shown while content loads.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = AppRadius.sm});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Placeholder cards for a list that is still loading, with a gentle pulse.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return _SkeletonPulse(
      child: ListView.separated(
        padding: AppSpacing.screen,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, __) => const AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: 160, height: 18),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox(width: 220),
          ]),
        ),
      ),
    );
  }
}

/// Placeholder for a detail page that is still loading: a title and subtitle, then [cards]
/// cards of label/value rows. Pulses like [SkeletonList].
class SkeletonDetail extends StatelessWidget {
  final int cards;
  final int rowsPerCard;
  const SkeletonDetail({super.key, this.cards = 2, this.rowsPerCard = 3});

  @override
  Widget build(BuildContext context) {
    return _SkeletonPulse(
      child: ListView(
        padding: AppSpacing.screen,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const SkeletonBox(width: 200, height: 24),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonBox(width: 120),
          for (var c = 0; c < cards; c++) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SkeletonBox(width: 140, height: 18),
                for (var r = 0; r < rowsPerCard; r++) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Row(children: [
                    SkeletonBox(width: 20, height: 20),
                    SizedBox(width: AppSpacing.md),
                    Expanded(child: SkeletonBox()),
                    SizedBox(width: AppSpacing.xl),
                    SkeletonBox(width: 64),
                  ]),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fades [child] in and out while content loads, and tells screen readers it is loading.
class _SkeletonPulse extends StatefulWidget {
  final Widget child;
  const _SkeletonPulse({required this.child});

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(label: 'Loading', child: FadeTransition(opacity: _pulse, child: widget.child));
  }
}

/// A large icon in a tinted circle, used by empty and error states.
class StateIcon extends StatelessWidget {
  final IconData icon;
  final StatusTone tone;
  const StateIcon(this.icon, {super.key, this.tone = StatusTone.info});

  @override
  Widget build(BuildContext context) {
    final colors = AppStatusColors.of(context, tone);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: colors.background, shape: BoxShape.circle),
      child: Icon(icon, size: 34, color: colors.foreground),
    );
  }
}
