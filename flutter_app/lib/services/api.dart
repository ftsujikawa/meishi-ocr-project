import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';

Future<List<dynamic>> uploadImage(String path) async {
  final f = File(path);
  if (!await f.exists()) {
    throw Exception('Image file not found: $path');
  }
  final size = await f.length();
  if (size == 0) {
    throw Exception('Image file is empty: $path');
  }

  final uri =
      Uri.parse('https://meishi-ocr-880513430131.asia-northeast1.run.app/ocr');

  final lower = path.toLowerCase();
  final mediaType = lower.endsWith('.png')
      ? MediaType('image', 'png')
      : MediaType('image', 'jpeg');
  final filename = lower.endsWith('.png') ? 'image.png' : 'image.jpg';

  final req = http.MultipartRequest('POST', uri);
  req.headers['Accept'] = 'application/json';
  req.files.add(
    await http.MultipartFile.fromPath(
      'file',
      path,
      filename: filename,
      contentType: mediaType,
    ),
  );

  final res = await req.send();
  final body = await res.stream.bytesToString();
  debugPrint(
    'OCR response: status=${res.statusCode}, body=${body.substring(0, body.length > 300 ? 300 : body.length)}',
  );

  final status = res.statusCode;

  if (status < 200 || status >= 300) {
    throw Exception(
      'OCR request failed ($status): $body (path=$path, size=$size)',
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
