import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/course.dart';
import 'course_image_color_detector.dart';
import 'course_image_layout.dart';

/// 课表截图识别：像素色块检测 + MLKit OCR + 块内文字归位。
///
/// 移动教务的课程不是规则文字表格，而是彩色长条。先检测色块再把 OCR
/// 结果聚类到色块，能避免把课程名按文字中心误吸附到错误节次。
class CourseImageParser {
  CourseImageParser({CourseImageColorDetector? colorDetector})
      : _colorDetector = colorDetector ?? const CourseImageColorDetector();

  final CourseImageColorDetector _colorDetector;

  /// 从相册选图并识别，返回课程列表（用户取消返回 null）。
  Future<List<Course>?> pickAndParse() async {
    final result = await pickAndParseResult();
    return result?.courses;
  }

  /// 返回置信度，供 UI 决定是否需要用户确认。
  Future<CourseImageParseResult?> pickAndParseResult() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
      maxWidth: 2400,
    );
    if (picked == null) return null;

    return parseFile(picked.path);
  }

  /// 复用真实本地 OCR 路径，供隔离设备回归直接传入图片。
  Future<CourseImageParseResult> parseFile(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final recognized = await recognizer.processImage(inputImage);
      final textBoxes = <OcrTextBox>[];
      for (final block in recognized.blocks) {
        // 行级框比 block 级框更适合标准总览表：课程名、周次、老师和
        // 教室通常各占一行，保留真实的垂直位置才能识别合并单元格。
        if (block.lines.isEmpty) {
          textBoxes.add(OcrTextBox(text: block.text, box: block.boundingBox));
        } else {
          textBoxes.addAll(
            block.lines.map((line) => OcrTextBox(
                  text: line.text,
                  box: line.boundingBox,
                  confidence: line.confidence,
                )),
          );
        }
      }
      final colorBlocks = _colorDetector.detect(await File(path).readAsBytes());
      return CourseImageLayoutParser().parse(
        textBoxes: textBoxes,
        colorBlocks: colorBlocks,
      );
    } finally {
      await recognizer.close();
    }
  }
}
