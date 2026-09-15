import 'package:flutter/material.dart';

/// Global Loading/Spinner Remediation wave (`UI-001`) — the canonical Niswah
/// loading indicator. Every button-loading and page-level loading state in
/// the app should use this instead of an ad hoc bare `CircularProgressIndicator`,
/// so sizing/contrast/semantics are governed in exactly one place.
///
/// Root-cause note (see `UI-001` in the finding register for the full
/// inventory/investigation): the concrete owner-reported case (the Create
/// Account button collapsing to a tiny dot) could not be reproduced from the
/// current code via direct widget-tree measurement — every existing button
/// site already wraps its `CircularProgressIndicator` in an explicit
/// `SizedBox`, confirmed rendering at the intended size with no distorting
/// ancestor (`Opacity`/`Transform`/`FittedBox`) — and this exact sizing has
/// been present since this repo's first tracked commit. This component
/// exists regardless, per the charter's own explicit instruction to
/// introduce one canonical indicator: it makes the "always give this an
/// explicit, non-negotiable size" contract impossible to accidentally skip
/// at any future call site, which a bare `CircularProgressIndicator` does
/// not enforce.
enum NiswahLoadingSize { small, medium, large }

enum NiswahLoadingContrast { light, dark }

class NiswahLoadingIndicator extends StatelessWidget {
  const NiswahLoadingIndicator({
    super.key,
    this.size = NiswahLoadingSize.medium,
    this.contrast = NiswahLoadingContrast.dark,
    this.color,
    this.semanticsLabel,
  });

  /// `small`: compact/inline controls (icon-button sends, small chips).
  /// `medium`: normal CTA buttons (the common case).
  /// `large`: page-level loading.
  final NiswahLoadingSize size;

  /// `light`: for a light-colored spinner on a dark/saturated background
  /// (most filled CTA buttons). `dark`: for a spinner on a light/white
  /// background (page-level loaders, cards). Ignored if [color] is given.
  final NiswahLoadingContrast contrast;

  /// Explicit override — takes precedence over [contrast] when the caller
  /// needs to match a specific brand color (e.g. a themed accent).
  final Color? color;

  /// Announced to a screen reader while loading (e.g. "Creating account" /
  /// "جارٍ إنشاء الحساب"). Omit only when an adjacent, already-visible status
  /// `Text` announces the same state — a bare `CircularProgressIndicator`
  /// with no `semanticsLabel` contributes zero nodes of its own (AU-014),
  /// so this never produces a duplicate announcement either way.
  final String? semanticsLabel;

  double get _dimension => switch (size) {
    NiswahLoadingSize.small => 15,
    NiswahLoadingSize.medium => 22,
    NiswahLoadingSize.large => 40,
  };

  double get _strokeWidth => switch (size) {
    NiswahLoadingSize.small => 2,
    NiswahLoadingSize.medium => 2.4,
    NiswahLoadingSize.large => 3,
  };

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ??
        (contrast == NiswahLoadingContrast.light
            ? Colors.white
            : const Color(0xFFE11D48));
    // Explicit dimensions on every instance, always — the parent's layout
    // is never trusted to determine this widget's visible size (Section C's
    // own explicit requirement).
    return SizedBox(
      width: _dimension,
      height: _dimension,
      child: CircularProgressIndicator(
        strokeWidth: _strokeWidth,
        color: resolvedColor,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}

/// Canonical loading-button behavior (Section D): a fixed-height CTA button
/// that shows its label normally, swaps to a stable-size spinner while
/// [loading], is never double-submittable (nulls `onPressed` while
/// loading), and never changes its own height/width between the two states.
class NiswahLoadingButton extends StatelessWidget {
  const NiswahLoadingButton({
    super.key,
    required this.loading,
    required this.onPressed,
    required this.label,
    this.style,
    this.height = 54,
    this.contrast = NiswahLoadingContrast.light,
    this.loadingSemanticsLabel,
  });

  final bool loading;
  final VoidCallback? onPressed;
  final String label;
  final ButtonStyle? style;
  final double height;
  final NiswahLoadingContrast contrast;
  final String? loadingSemanticsLabel;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: height,
    child: FilledButton(
      onPressed: loading ? null : onPressed,
      style: style,
      child: loading
          ? NiswahLoadingIndicator(
              contrast: contrast,
              semanticsLabel: loadingSemanticsLabel,
            )
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}
