// CameraPreview + ガイド枠 UI（省略なし）

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import 'edit_page_fixed.dart';

class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraPage({super.key, required this.cameras});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _capturedImagePath;
  bool _isOcrRunning = false;
  bool _isTakingPicture = false;

  Widget _buildGuideFrame(BoxConstraints constraints, Orientation orientation) {
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;

    final isPortrait = orientation == Orientation.portrait;

    final guideW = isPortrait ? maxW * 0.86 : maxW * 0.62;
    final guideH = isPortrait ? maxH * 0.32 : maxH * 0.72;

    return SizedBox(
      width: guideW,
      height: guideH,
      child: AspectRatio(
        aspectRatio: 1.6,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.cameras.isNotEmpty) {
      _controller = CameraController(
        widget.cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _initializeFuture = _controller!.initialize();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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
      if (!mounted) return;
      setState(() {
        _isTakingPicture = false;
      });
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
      if (!mounted) return;
      setState(() {
        _isOcrRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initializeFuture = _initializeFuture;
    final capturedImagePath = _capturedImagePath;

    if (controller == null || initializeFuture == null) {
      return const Scaffold(
        body: Center(child: Text('No camera available')),
      );
    }

    return Scaffold(
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

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller),
                      Center(
                        child: _buildGuideFrame(constraints, orientation),
                      ),
                      if (capturedImagePath != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.black.withOpacity(0.6),
                            padding: const EdgeInsets.all(16),
                            child: SafeArea(
                              top: false,
                              child: isPortrait
                                  ? Row(
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
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ElevatedButton(
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
                                        const SizedBox(height: 8),
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
