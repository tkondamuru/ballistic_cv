import 'package:flutter/material.dart';

class CameraReticle extends StatelessWidget {
  final double size;
  final String label;

  const CameraReticle({
    super.key,
    this.size = 140.0,
    this.label = 'Align Ball Here',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer glowing pulsing ring
            Container(
              width: size + 20,
              height: size + 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00FF66).withValues(alpha: 0.35),
                  width: 3.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FF66).withValues(alpha: 0.25),
                    blurRadius: 16,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),

            // Inner dashed target reticle
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00FF66),
                  width: 2.5,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Center dot
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  // Horizontal line
                  Container(
                    width: 24,
                    height: 1.5,
                    color: const Color(0xFF00FF66).withValues(alpha: 0.6),
                  ),
                  // Vertical line
                  Container(
                    width: 1.5,
                    height: 24,
                    color: const Color(0xFF00FF66).withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF00FF66).withValues(alpha: 0.5)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
