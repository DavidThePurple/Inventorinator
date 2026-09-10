String supplierImageUrl(dynamic value) {
  if (value is Map) value = value['src'] ?? value['url'];
  if (value is! String) return '';
  var text = value.trim();
  if (text.startsWith('//')) text = 'https:$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return '';
  }
  return uri.removeFragment().toString();
}
