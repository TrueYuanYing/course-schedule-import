/// Only explicit product paths identify a family. An unrelated SSO hostname or
/// a school name is insufficient; this does not certify a successful import.
String? knownJwxtSystemFamily(String url, [int depth = 0]) {
  if (url.length > 4096 || depth > 2) return null;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return null;
  }
  final path = uri.path.toLowerCase();
  if (RegExp(r'/eams(?:/|5|$)').hasMatch(path)) return 'eams';
  if (RegExp(r'/(?:[^/]*_)?jsxsd(?:/|$)').hasMatch(path)) return 'qz';
  if (RegExp(r'/gmis(?:\d)?(?:/|$)').hasMatch(path)) return 'nanruan';
  try {
    for (final key in ['service', 'redirect_uri', 'redirect_url', 'target']) {
      final target = uri.queryParameters[key];
      if (target == null) continue;
      final family = knownJwxtSystemFamily(target, depth + 1);
      if (family != null) return family;
    }
  } on FormatException {
    return null;
  }
  return null;
}
