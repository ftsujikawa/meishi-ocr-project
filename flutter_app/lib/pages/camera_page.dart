// CameraPreview + ガイド枠 UI（省略なし）

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api.dart';
import 'edit_page_fixed.dart';

class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraPage({super.key, required this.cameras});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _capturedImagePath;
  bool _isOcrRunning = false;
  bool _isTakingPicture = false;
  String? _cameraInitError;
  Size? _lastSize;
  Orientation? _lastOrientation;

  Widget _buildGuideFrame(BoxConstraints constraints, Orientation orientation) {
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;

    const aspect = 1.6;
    final isPortrait = orientation == Orientation.portrait;

    double guideW;
    double guideH;
    if (isPortrait) {
      guideW = maxW * 0.9;
      guideH = guideW / aspect;
      final hCap = maxH * 0.5;
      if (guideH > hCap) {
        guideH = hCap;
        guideW = guideH * aspect;
      }
    } else {
      guideH = maxH * 0.8;
      guideW = guideH * aspect;
      final wCap = maxW * 0.7;
      if (guideW > wCap) {
        guideW = wCap;
        guideH = guideW / aspect;
      }
    }

    return SizedBox(
      width: guideW,
      height: guideH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (widget.cameras.isNotEmpty) {
      _controller = CameraController(
        widget.cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _initializeFuture = _controller!.initialize();
      _initializeFuture!.then((_) {
        SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      });
      _initializeFuture!.catchError((e, st) {
        if (!mounted) return;
        setState(() {
          _cameraInitError = e.toString();
        });
      });
    } else {
      _cameraInitError = 'カメラが見つかりませんでした';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    debugPrint('didChangeMetrics size=$size');
    super.didChangeMetrics();
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    final initializeFuture = _initializeFuture;
    if (controller == null || initializeFuture == null) return;

    if (_isTakingPicture) return;
    if (controller.value.isTakingPicture) return;
    setState(() {
      _isTakingPicture = true;
    });

    try {
      await initializeFuture;
      if (!mounted) return;
      final XFile file = await controller.takePicture();
      if (!mounted) return;

      setState(() {
        _capturedImagePath = file.path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: ${file.path}')),
      );
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: ${e.description ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
    }
  }

  Future<void> _runOcr() async {
    final path = _capturedImagePath;
    if (path == null) return;

    setState(() {
      _isOcrRunning = true;
    });

    try {
      final blocks = await uploadImage(path);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditPage(imagePath: path, blocks: blocks),
        ),
      );
      if (!mounted) return;
      setState(() {
        _capturedImagePath = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOcrRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initializeFuture = _initializeFuture;
    final capturedImagePath = _capturedImagePath;

    final mq = MediaQuery.of(context);
    final orientation = mq.orientation;
    final size = mq.size;
    if (_lastOrientation != orientation || _lastSize != size) {
      _lastOrientation = orientation;
      _lastSize = size;
      debugPrint('MediaQuery orientation=$orientation size=$size');
    }

    if (controller == null || initializeFuture == null) {
      final msg = _cameraInitError ?? 'No camera available';
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '$msg\n\n(iOSシミュレータの場合、カメラが利用できないことがあります。実機でお試しください。)',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (context, orientation) {
          return FutureBuilder<void>(
            future: initializeFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isPortrait = orientation == Orientation.portrait;
                  final previewSize = controller.value.previewSize;
                  final previewW = previewSize == null
                      ? (isPortrait
                          ? (1 / controller.value.aspectRatio)
                          : controller.value.aspectRatio)
                      : (isPortrait ? previewSize.height : previewSize.width);
                  final previewH = previewSize == null
                      ? 1.0
                      : (isPortrait ? previewSize.width : previewSize.height);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: ClipRect(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: previewW,
                              height: previewH,
                              child: CameraPreview(controller),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: _buildGuideFrame(constraints, orientation),
                      ),
                      if (capturedImagePath != null)
                        if (isPortrait)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.6),
                              padding: const EdgeInsets.all(16),
                              child: SafeArea(
                                top: false,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed:
                                            _isOcrRunning ? null : _runOcr,
                                        child: _isOcrRunning
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Text('OCR'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton(
                                      onPressed: _isOcrRunning
                                          ? null
                                          : () {
                                              setState(() {
                                                _capturedImagePath = null;
                                              });
                                            },
                                      child: const Text('撮り直す'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          Positioned(
                            top: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 220,
                              color: Colors.black.withValues(alpha: 0.6),
                              padding: const EdgeInsets.all(16),
                              child: SafeArea(
                                left: false,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ElevatedButton(
                                      onPressed: _isOcrRunning ? null : _runOcr,
                                      child: _isOcrRunning
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('OCR'),
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton(
                                      onPressed: _isOcrRunning
                                          ? null
                                          : () {
                                              setState(() {
                                                _capturedImagePath = null;
                                              });
                                            },
                                      child: const Text('撮り直す'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: (_isOcrRunning || _isTakingPicture) ? null : _takePicture,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}
