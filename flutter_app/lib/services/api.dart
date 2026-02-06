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

  final uri = Uri.parse(
      'https://meishi-ocr-880513430131.asia-northeast1.run.app/ocr?use_llm=true');

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

  List<dynamic>? extractBlocks(Map<String, dynamic> root) {
    final direct = root['blocks'];
    if (direct is List) return direct;

    final result = root['result'];
    if (result is Map<String, dynamic>) {
      final nested = result['blocks'];
      if (nested is List) return nested;
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        final nested2 = data['blocks'];
        if (nested2 is List) return nested2;
      }
    }

    final data = root['data'];
    if (data is Map<String, dynamic>) {
      final nested = data['blocks'];
      if (nested is List) return nested;
    }

    final items = root['items'];
    if (items is List) return items;

    return null;
  }

  final blocks = extractBlocks(decoded);
  if (blocks == null) {
    throw Exception('Missing/invalid blocks in OCR response: $decoded');
  }

  Map<String, dynamic>? normalizeBlock(dynamic block) {
    if (block == null) return null;

    if (block is Map) {
      final map = Map<String, dynamic>.from(block);
      final dynamic text =
          map['text'] ?? map['value'] ?? map['raw'] ?? map['content'];
      final dynamic conf = map['confidence'] ?? map['score'];
      if (text == null) {
        return <String, dynamic>{...map};
      }
      return <String, dynamic>{
        ...map,
        'text': text.toString(),
        if (conf != null) 'confidence': conf,
      };
    }

    if (block is String) {
      final s = block.trim();
      if (s.isEmpty) return null;
      return <String, dynamic>{'text': s};
    }

    if (block is List && block.length >= 2) {
      // PaddleOCR系でありがちな [points, [text, score]] を吸収
      final second = block[1];
      if (second is List && second.isNotEmpty) {
        final text = second[0];
        final conf = second.length >= 2 ? second[1] : null;
        if (text != null) {
          return <String, dynamic>{
            'text': text.toString(),
            if (conf != null) 'confidence': conf,
            'raw': block,
          };
        }
      }
      // それ以外は文字列化して持つ
      return <String, dynamic>{'text': block.toString(), 'raw': block};
    }

    final s = block.toString().trim();
    if (s.isEmpty) return null;
    return <String, dynamic>{'text': s};
  }

  final normalized = <dynamic>[];
  for (final b in blocks) {
    final nb = normalizeBlock(b);
    if (nb != null) normalized.add(nb);
  }

  return normalized;
}
