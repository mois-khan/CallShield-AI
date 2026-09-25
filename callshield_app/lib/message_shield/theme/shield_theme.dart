import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for Message Shield. Values intentionally match the existing
/// CallShield look (dark slate surfaces, indigo accent) so the new section feels
/// like part of the same app.
class ShieldTheme {
  const ShieldTheme._();

  static const Color background = Color(0xFF0F172A);
  static const Color surface = Color(0xFF1E1E2A);
  static const Color surfaceAlt = Color(0xFF1E293B);
  static const Color accent = Color(0xFF6366F1);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color safe = Color(0xFF10B981);
  static const Color textPrimary = Colors.white;
  static const Color textMuted = Color(0xFF94A3B8);

  static const Color legitCategory = Color(0xFF64748B);

  static TextStyle title({double size = 18}) => GoogleFonts.plusJakartaSans(
        color: textPrimary,
        fontWeight: FontWeight.bold,
        fontSize: size,
      );

  static TextStyle body({double size = 14, Color? color}) => GoogleFonts.plusJakartaSans(
        color: color ?? textMuted,
        fontSize: size,
      );

  static TextStyle mono({double size = 14, Color? color}) => GoogleFonts.firaCode(
        color: color ?? textPrimary,
        fontSize: size,
        fontWeight: FontWeight.bold,
      );

  static BoxDecoration card({Color? border, Color? color}) => BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border ?? Colors.white.withValues(alpha: 0.08)),
      );

  static BoxDecoration pill(Color color) => BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      );
}
