import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'pages/camera_page.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '名刺OCR',
      theme: ThemeData(useMaterial3: true),
      home: CameraPage(cameras: cameras),
    );
  }
}
