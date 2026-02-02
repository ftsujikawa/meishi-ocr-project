import 'package:http/http.dart' as http;
import 'dart:convert';

Future<List<dynamic>> uploadImage(String path) async {
  final req = http.MultipartRequest(
    'POST',
    Uri.parse('https://meishi-ocr-880513430131.asia-northeast1.run.app/ocr'),
  );

  req.files.add(await http.MultipartFile.fromPath('file', path));
  final res = await req.send();
  final body = await res.stream.bytesToString();
  return json.decode(body)['blocks'];
}
