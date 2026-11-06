import 'package:flutter/material.dart';

import '../../services/course/school_badge_assets.dart';

class SchoolBadge extends StatelessWidget {
  const SchoolBadge({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final base = name
        .replaceFirst(
            RegExp(r'\s*(?:[-·]\s*)?(?:[（(]?(?:研究生(?:院)?|本科生?)[）)]?)$'), '')
        .trim()
        .replaceFirst(RegExp(r'[（(](?:20\d{2}新版|新|旧|微人大|自动导入时间)[）)]$'), '')
        .trim();
    final asset = schoolBadgeAssets[name] ?? schoolBadgeAssets[base];
    Widget fallback() {
      const colors = [
        Color(0xff4b8d8a),
        Color(0xff986caa),
        Color(0xffa57b48),
        Color(0xff5f81b6),
        Color(0xffb16d81),
        Color(0xff719246)
      ];
      const icons = [
        Icons.auto_stories_rounded,
        Icons.local_library_rounded,
        Icons.school_rounded,
        Icons.spa_rounded,
        Icons.science_rounded,
        Icons.wb_sunny_rounded
      ];
      final hash = base.runes.fold<int>(0, (value, rune) => value * 31 + rune) &
          0x7fffffff;
      final color = colors[hash % colors.length];
      return DecoratedBox(
          decoration: BoxDecoration(
              color: color.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? .25
                      : .12),
              borderRadius: BorderRadius.circular(12)),
          child: Center(
              child: Icon(icons[(hash ~/ 7) % icons.length],
                  color: color, size: 22)));
    }

    return ExcludeSemantics(
      child: SizedBox(
        width: 36,
        height: 36,
        child: asset == null
            ? fallback()
            : DecoratedBox(
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Image.asset(asset,
                      fit: BoxFit.contain,
                      cacheWidth: 96,
                      cacheHeight: 96,
                      errorBuilder: (_, __, ___) => fallback()),
                ),
              ),
      ),
    );
  }
}
