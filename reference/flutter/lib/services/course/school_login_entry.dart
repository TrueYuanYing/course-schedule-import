/// Resolve only the known bare HFUT entry; never alter authenticated callbacks.
Uri schoolStudentLoginEntry(Uri uri) {
  if (uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'gmsstu.hfut.edu.cn' &&
      (!uri.hasPort || uri.port == 443) &&
      !uri.authority.contains('@') &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (uri.path.isEmpty || uri.path == '/')) {
    return Uri.parse('https://gmsstu.hfut.edu.cn/logon');
  }
  return uri;
}
