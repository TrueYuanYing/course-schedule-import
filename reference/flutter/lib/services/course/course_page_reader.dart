import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'academic_import_result.dart';

/// Both Android import surfaces execute the same bundled collector and parser.
/// University scripts are never evaluated locally or given a native bridge.
class CoursePageReader {
  static const _assets = 'android/jwimport/src/main/assets/jwimport/';
  static List<String>? _scripts;
  static String? _watch;

  /// Cheap local visibility check. Only a changed timetable triggers parsing.
  static Future<String> signature(WebViewController controller) async {
    final script = _watch ??= await rootBundle.loadString('${_assets}watch.js');
    final value = _decode(await controller
        .runJavaScriptReturningResult(script)
        .timeout(const Duration(seconds: 3)));
    return value is String && RegExp(r'^\d{1,8}:\d{1,10}$').hasMatch(value)
        ? value
        : '';
  }

  static Future<AcademicImportResult> read(
    WebViewController controller, {
    required String school,
    bool Function()? isActive,
  }) async {
    final scripts = _scripts ??= await Future.wait([
      rootBundle.loadString('${_assets}provider.js'),
      rootBundle.loadString('${_assets}parser.js'),
    ]);
    final id = jsonEncode(DateTime.now().microsecondsSinceEpoch.toString());
    final deadline = DateTime.now().add(const Duration(seconds: 13));
    void checkActive() {
      if (isActive?.call() == false) {
        throw const CoursePageReadException('读取已取消');
      }
    }

    checkActive();
    await controller.runJavaScript('''${scripts[0]}
window.__ikoCourseRead84={id:$id,data:window.__campusCapture,href:location.href};
''').timeout(const Duration(seconds: 4));
    try {
      while (DateTime.now().isBefore(deadline)) {
        checkActive();
        final status = await controller.runJavaScriptReturningResult('''
(() => {const read=window.__ikoCourseRead84;
if(!read||read.id!==$id||read.href!==location.href)return 'changed';
return read.data.done?'ready':'waiting';})()
''').timeout(const Duration(seconds: 3));
        final state = _decode(status);
        if (state == 'changed') {
          throw const CoursePageReadException('页面已切换，请等待当前课表加载后重新读取。');
        }
        if (state != 'ready') {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        final value = await controller.runJavaScriptReturningResult('''
(() => {
const module={exports:{}};
${scripts[1]}
const read=window.__ikoCourseRead84;
if(!read||read.id!==$id||read.href!==location.href)return JSON.stringify({ok:false,message:'页面已切换，请重新读取。'});
const capture=read.data;
try{return JSON.stringify({ok:true,result:{schemaVersion:1,school:${jsonEncode(school)},...module.exports.parseCapture(capture)}});}
catch(error){return JSON.stringify({ok:false,message:String(error.message),hasTimetable:capture.hasTimetable===true,frameUrls:capture.frameUrls||[]});}
})()
''').timeout(const Duration(seconds: 4));
        checkActive();
        final document = _decode(value);
        if (document is! Map) {
          throw const CoursePageReadException('课表读取结果无效，请重新读取。');
        }
        if (document['ok'] == true) {
          return AcademicImportResult.parse(jsonEncode(document['result']));
        }
        throw CoursePageReadException(
          document['message'] is String
              ? document['message'] as String
              : '当前页课表格式尚未识别。',
          hasTimetable: document['hasTimetable'] == true,
          frameUrls: [
            for (final raw in (document['frameUrls'] is List
                ? document['frameUrls'] as List
                : const []))
              if (raw is String)
                if (_frameUri(raw) case final Uri uri) uri,
          ],
        );
      }
      throw const CoursePageReadException('读取课表超时。学校登录状态已保留，可重新读取。');
    } on TimeoutException {
      throw const CoursePageReadException('学校页面暂时没有响应。登录状态已保留，可重新读取。');
    } finally {
      // Clear only this read; never a newer read or the authenticated page.
      await controller.runJavaScript('''
if(window.__ikoCourseRead84?.id===$id)delete window.__ikoCourseRead84;
''').timeout(const Duration(seconds: 2)).catchError((_) {});
    }
  }

  static Object? _decode(Object value) {
    Object? result = value;
    for (var index = 0; index < 2 && result is String; index++) {
      try {
        result = jsonDecode(result);
      } on FormatException {
        break;
      }
    }
    return result;
  }

  static Uri? _frameUri(String raw) {
    final uri = Uri.tryParse(raw);
    return uri != null &&
            raw.length <= 4096 &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }
}

class CoursePageReadException implements Exception {
  const CoursePageReadException(this.message,
      {this.hasTimetable = false, this.frameUrls = const []});
  final String message;
  final bool hasTimetable;
  final List<Uri> frameUrls;
}
