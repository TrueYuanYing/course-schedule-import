import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'dart:math' as math;

import 'package:image/image.dart' as image;

import 'course_image_layout.dart';

/// 用像素饱和度找彩色课程块，不依赖云端视觉模型。
class CourseImageColorDetector {
  const CourseImageColorDetector();

  List<CourseColorBlock> detect(Uint8List bytes) {
    final source = image.decodeImage(bytes);
    if (source == null || source.width == 0 || source.height == 0) {
      return const [];
    }

    final step = math.max(1, math.max(source.width, source.height) ~/ 640);
    final width = (source.width / step).ceil();
    final height = (source.height / step).ceil();
    final mask = List<bool>.filled(width * height, false);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = source.getPixel(
          math.min(source.width - 1, x * step),
          math.min(source.height - 1, y * step),
        );
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final maxChannel = math.max(r, math.max(g, b));
        final minChannel = math.min(r, math.min(g, b));
        mask[y * width + x] = maxChannel > 90 &&
            (maxChannel - minChannel) > 24 &&
            ((maxChannel - minChannel) / maxChannel) > 0.16;
      }
    }

    final visited = List<bool>.filled(mask.length, false);
    final blocks = <CourseColorBlock>[];
    final minPixels = math.max(12, (width * height * 0.00012).round());
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final start = y * width + x;
        if (visited[start] || !mask[start]) continue;
        final queue = <int>[start];
        visited[start] = true;
        var count = 0;
        var minX = x;
        var maxX = x;
        var minY = y;
        var maxY = y;
        for (var cursor = 0; cursor < queue.length; cursor++) {
          final current = queue[cursor];
          final currentX = current % width;
          final currentY = current ~/ width;
          count++;
          minX = math.min(minX, currentX);
          maxX = math.max(maxX, currentX);
          minY = math.min(minY, currentY);
          maxY = math.max(maxY, currentY);
          for (final neighbor in [
            if (currentX > 0) current - 1,
            if (currentX + 1 < width) current + 1,
            if (currentY > 0) current - width,
            if (currentY + 1 < height) current + width,
          ]) {
            if (!visited[neighbor] && mask[neighbor]) {
              visited[neighbor] = true;
              queue.add(neighbor);
            }
          }
        }
        if (count < minPixels) continue;
        final rect = Rect.fromLTRB(
          minX * step.toDouble(),
          minY * step.toDouble(),
          math.min(source.width, (maxX + 1) * step).toDouble(),
          math.min(source.height, (maxY + 1) * step).toDouble(),
        );
        if (rect.width >= 12 && rect.height >= 12) {
          blocks.add(CourseColorBlock(rect));
        }
      }
    }
    return blocks;
  }
}
