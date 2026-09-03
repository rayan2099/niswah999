import 'package:flutter/material.dart';

/// The Niswah brand mark — a woman's profile with flowing hair forming a
/// crescent, and a lotus blooming at the neckline.
class NiswahLogo extends StatelessWidget {
  const NiswahLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/logo.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
  );
}
