// 信頼度で背景色を変える編集画面

import 'dart:io';

import 'package:flutter/material.dart';
import '../services/api.dart';

class EditPage extends StatefulWidget {
  final String imagePath;

  const EditPage({super.key, required this.imagePath});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  bool _isUploading = false;
  String? _error;
  List<dynamic>? _blocks;

  Future<void> _runOcr() async {
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
      _error = null;
    });

    try {
      final blocks = await uploadImage(widget.imagePath);
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('編集'),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('画像を表示できませんでした: $error'),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isUploading ? null : _runOcr,
                        icon: _isUploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload),
                        label: Text(_isUploading ? 'OCR中...' : 'OCRを実行'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            if (_blocks == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('OCR結果はまだありません')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverList.separated(
                  itemCount: _blocks!.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final b = _blocks![index];
                    final text = (b is Map && b['text'] != null)
                        ? b['text'].toString()
                        : b.toString();
                    final conf = (b is Map && b['confidence'] is num)
                        ? (b['confidence'] as num).toDouble()
                        : null;

                    final subtitle = conf == null
                        ? null
                        : 'confidence: ${conf.toStringAsFixed(2)}';

                    return Card(
                      child: ListTile(
                        title: Text(text),
                        subtitle: subtitle == null ? null : Text(subtitle),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
