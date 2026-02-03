import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

Future<List<dynamic>> uploadImage(String path) async {
  final f = File(path);
  if (!await f.exists()) {
    throw Exception('Image file not found: $path');
  }
  final size = await f.length();
  if (size == 0) {
    throw Exception('Image file is empty: $path');
  }

  final req = http.MultipartRequest(
    'POST',
    Uri.parse('https://meishi-ocr-880513430131.asia-northeast1.run.app/ocr'),
  );

  req.headers['Accept'] = 'application/json';

  req.files.add(
    await http.MultipartFile.fromPath(
      'file',
      path,
      filename: 'image.jpg',
    ),
  );
  final res = await req.send();
  final body = await res.stream.bytesToString();
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception(
      'OCR request failed (${res.statusCode}): $body (path=$path, size=$size)',
    );
  }

  final decoded = json.decode(body);
  if (decoded is! Map<String, dynamic>) {
    throw Exception('Unexpected OCR response: $decoded');
  }

  final blocks = decoded['blocks'];
  if (blocks is! List) {
    throw Exception('Missing/invalid blocks in OCR response: $decoded');
  }

  return blocks;
}
