// 信頼度で背景色を変える編集画面

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '_card_data.dart';

class EditPage extends StatefulWidget {
  final String imagePath;
  final List<dynamic> blocks;

  const EditPage({super.key, required this.imagePath, required this.blocks});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditableBlock {
  final TextEditingController controller;
  final double? confidence;
  final Map<String, dynamic>? raw;
  final Set<String> labels;

  _EditableBlock({
    required this.controller,
    required this.confidence,
    required this.raw,
    required this.labels,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...(raw ?? const <String, dynamic>{}),
      'text': controller.text,
      'labels': labels.toList(growable: false),
      if (confidence != null) 'confidence': confidence,
    };
  }
}

class _EditPageState extends State<EditPage> {
  static const List<String> _availableLabels = <String>[
    '氏名',
    '会社',
    '部署',
    '役職',
    '電話',
    '携帯',
    'FAX',
    'メール',
    '郵便番号',
    '住所',
    'URL',
    'その他',
  ];

  late final List<_EditableBlock> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.blocks.map(_parseBlock).toList();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.controller.dispose();
    }
    super.dispose();
  }

  _EditableBlock _parseBlock(dynamic block) {
    if (block is Map) {
      final map = Map<String, dynamic>.from(block);
      final text = (map['text'] ?? map['value'] ?? map['raw'] ?? '').toString();
      final confidence = _toDouble(map['confidence'] ?? map['score']);

      final labels = <String>{};
      final rawLabels = map['labels'] ?? map['attrs'] ?? map['attributes'];
      if (rawLabels is List) {
        for (final v in rawLabels) {
          final s = v?.toString().trim();
          if (s != null && s.isNotEmpty) labels.add(s);
        }
      } else if (rawLabels is String) {
        for (final s in rawLabels.split(',')) {
          final t = s.trim();
          if (t.isNotEmpty) labels.add(t);
        }
      }

      labels.addAll(_inferLabels(text));

      return _EditableBlock(
        controller: TextEditingController(text: text),
        confidence: confidence,
        raw: map,
        labels: labels,
      );
    }

    final text = block?.toString() ?? '';
    return _EditableBlock(
      controller: TextEditingController(text: text),
      confidence: null,
      raw: null,
      labels: _inferLabels(text),
    );
  }

  Set<String> _inferLabels(String text) {
    final t = text.trim();
    if (t.isEmpty) return <String>{};

    final labels = <String>{};

    final emailRe =
        RegExp(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", caseSensitive: false);
    final urlRe = RegExp(r"\bhttps?://\S+|\bwww\.[^\s]+", caseSensitive: false);
    final postalRe = RegExp(r"〒?\s*\d{3}-?\d{4}");

    if (emailRe.hasMatch(t)) {
      labels.add('メール');
    }
    if (urlRe.hasMatch(t)) {
      labels.add('URL');
    }
    if (postalRe.hasMatch(t)) {
      labels.add('郵便番号');
    }

    final hasFaxWord =
        RegExp(r"\bFAX\b|ＦＡＸ|ﾌｧｯｸｽ|ファックス|ファクス|ＦＡＸ：|FAX：", caseSensitive: false)
            .hasMatch(t);
    if (hasFaxWord) {
      labels.add('FAX');
    }

    final hasTelWord =
        RegExp(r"\bTEL\b|ＴＥＬ|電話|TEL：|ＴＥＬ：", caseSensitive: false).hasMatch(t);
    if (hasTelWord) {
      labels.add('電話');
    }

    final hasMobileWord =
        RegExp(r"携帯|Mobile|Cell|スマホ|MOBILE|携帯：|携帯電話", caseSensitive: false)
            .hasMatch(t);
    if (hasMobileWord) {
      labels.add('携帯');
    }

    final phoneRe = RegExp(r"\+?\d[\d\-()\s]{7,}\d");
    if (phoneRe.hasMatch(t) &&
        !labels.contains('FAX') &&
        !labels.contains('電話') &&
        !labels.contains('携帯')) {
      labels.add('電話');
    }

    final looksAddress = RegExp(
            r"(都|道|府|県).*(市|区|町|村)|丁目|番地|号|ビル|Building|Bldg",
            caseSensitive: false)
        .hasMatch(t);
    if (looksAddress) {
      labels.add('住所');
    }

    final looksCompany = RegExp(
            r"株式会社|有限会社|合同会社|Inc\.?|Ltd\.?|Co\.?\s*Ltd\.?|Corporation|会社",
            caseSensitive: false)
        .hasMatch(t);
    if (looksCompany) {
      labels.add('会社');
    }

    final looksDept = RegExp(r"部|課|室|局|本部|センター|研究所|Div\.?|Dept\.?|Department",
            caseSensitive: false)
        .hasMatch(t);
    if (looksDept) {
      labels.add('部署');
    }

    final looksTitle = RegExp(
            r"社長|取締役|代表|部長|課長|主任|マネージャ|Manager|CEO|CTO|CFO|COO|Director|President",
            caseSensitive: false)
        .hasMatch(t);
    if (looksTitle) {
      labels.add('役職');
    }

    final looksName = RegExp(
            r"^[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}A-Za-z\s]{2,}$",
            unicode: true)
        .hasMatch(t);
    if (looksName && labels.isEmpty) {
      labels.add('氏名');
    }

    if (labels.isEmpty) {
      labels.add('その他');
    }

    return labels;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Color _backgroundForConfidence(double? c) {
    if (c == null) return Colors.transparent;
    if (c >= 0.9) return Colors.green.withOpacity(0.15);
    if (c >= 0.7) return Colors.yellow.withOpacity(0.2);
    return Colors.red.withOpacity(0.12);
  }

  void _save() {
    final edited = _items.map((e) => e.toJson()).toList(growable: false);
    Navigator.of(context).pop(edited);
  }

  CardData _extractCard() {
    final data = CardData();

    for (final item in _items) {
      final text = item.controller.text.trim();
      if (text.isEmpty) continue;

      final labels = item.labels;
      if (labels.contains('氏名')) {
        data.names.add(text);
      }
      if (labels.contains('会社')) {
        data.companies.add(text);
      }
      if (labels.contains('部署')) {
        data.departments.add(text);
      }
      if (labels.contains('役職')) {
        data.titles.add(text);
      }
      if (labels.contains('メール')) {
        data.emails.addAll(_extractEmails(text));
      }
      if (labels.contains('URL')) {
        data.urls.addAll(_extractUrls(text));
      }
      if (labels.contains('郵便番号')) {
        final p = _extractPostal(text);
        if (p != null) data.postalCodes.add(p);
      }
      if (labels.contains('住所')) {
        data.addresses.add(text);
      }

      if (labels.contains('電話')) {
        data.phones.addAll(_extractPhones(text));
      }
      if (labels.contains('携帯')) {
        data.mobiles.addAll(_extractPhones(text));
      }
      if (labels.contains('FAX')) {
        data.faxes.addAll(_extractPhones(text));
      }
    }

    return data;
  }

  List<String> _extractEmails(String text) {
    final emailRe =
        RegExp(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", caseSensitive: false);
    return emailRe
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList(growable: false);
  }

  List<String> _extractUrls(String text) {
    final urlRe = RegExp(r"\bhttps?://\S+|\bwww\.[^\s]+", caseSensitive: false);
    return urlRe
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList(growable: false);
  }

  String? _extractPostal(String text) {
    final postalRe = RegExp(r"〒?\s*(\d{3}-?\d{4})");
    final m = postalRe.firstMatch(text);
    if (m == null) return null;
    return m.group(1);
  }

  List<String> _extractPhones(String text) {
    final phoneRe = RegExp(r"\+?\d[\d\-()\s]{7,}\d");
    final results = <String>{};
    for (final m in phoneRe.allMatches(text)) {
      final raw = m.group(0);
      if (raw == null) continue;
      final normalized = raw.replaceAll(RegExp(r"\s+"), '').trim();
      if (normalized.isNotEmpty) results.add(normalized);
    }
    return results.toList(growable: false);
  }

  Future<void> _addToContacts() async {
    final card = _extractCard();
    if (card.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('追加する情報がありません')),
      );
      return;
    }

    final otherLines = <String>[];
    for (final item in _items) {
      final text = item.controller.text.trim();
      if (text.isEmpty) continue;
      if (item.labels.contains('その他')) {
        otherLines.add(text);
      }
    }

    final granted = await FlutterContacts.requestPermission(readonly: false);
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('連絡先へのアクセスが許可されていません')),
      );
      return;
    }

    final contact = Contact();
    final name = card.primaryName;
    if (name != null) {
      contact.name = Name(first: name);
    }

    final company = card.primaryCompany;
    if (company != null) {
      contact.organizations = [
        Organization(
          company: company,
          title: card.primaryTitle ?? '',
          department: card.primaryDepartment ?? '',
        ),
      ];
    }

    final phones = <Phone>[];
    for (final p in card.phones) {
      phones.add(Phone(p, label: PhoneLabel.work));
    }
    for (final p in card.mobiles) {
      phones.add(Phone(p, label: PhoneLabel.mobile));
    }
    for (final p in card.faxes) {
      phones.add(Phone(p, label: PhoneLabel.faxWork));
    }
    contact.phones = phones;

    contact.emails = card.emails
        .map((e) => Email(e, label: EmailLabel.work))
        .toList(growable: false);

    if (card.primaryAddressLine != null || card.primaryPostalCode != null) {
      contact.addresses = [
        Address(
          '',
          street: card.primaryAddressLine ?? '',
          postalCode: card.primaryPostalCode ?? '',
          label: AddressLabel.work,
        ),
      ];
    }

    if (otherLines.isNotEmpty) {
      contact.notes = [Note(otherLines.join('\n'))];
    }

    final inserted = await FlutterContacts.insertContact(contact);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          inserted.id.isNotEmpty ? '電話帳に追加しました' : '電話帳への追加に失敗しました',
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    final card = _extractCard();
    if (card.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('出力する情報がありません')),
      );
      return;
    }

    final header = <String>[
      '氏名',
      '会社',
      '部署',
      '役職',
      '電話',
      '携帯',
      'FAX',
      'メール',
      '郵便番号',
      '住所',
      'URL',
    ];

    final row = <String>[
      card.primaryName ?? '',
      card.primaryCompany ?? '',
      card.primaryDepartment ?? '',
      card.primaryTitle ?? '',
      card.phones.join(' / '),
      card.mobiles.join(' / '),
      card.faxes.join(' / '),
      card.emails.join(' / '),
      card.primaryPostalCode ?? '',
      card.primaryAddressLine ?? '',
      card.urls.join(' / '),
    ];

    final csv = '${_toCsvLine(header)}\n${_toCsvLine(row)}\n';

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/meishi_ocr_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv, flush: true);

    if (!mounted) return;
    await Share.shareXFiles(
      [XFile(file.path)],
      text: '名刺OCRのCSV',
    );
  }

  String _toCsvLine(List<String> fields) {
    return fields.map(_escapeCsv).join(',');
  }

  String _escapeCsv(String v) {
    final needsQuote =
        v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
    final escaped = v.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR結果編集'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
          IconButton(
            onPressed: _addToContacts,
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: '電話帳に追加',
          ),
          IconButton(
            onPressed: _exportCsv,
            icon: const Icon(Icons.file_upload),
            tooltip: 'CSV出力',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 1.6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: _backgroundForConfidence(_items[i].confidence),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('#${i + 1}'),
                        const Spacer(),
                        if (_items[i].confidence != null)
                          Text('conf: ${_items[i].confidence!.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _items[i].controller,
                      maxLines: null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: const Text('属性'),
                      subtitle: _items[i].labels.isEmpty
                          ? const Text('未選択')
                          : Text(_items[i].labels.join(' / ')),
                      children: [
                        for (final label in _availableLabels)
                          CheckboxListTile(
                            value: _items[i].labels.contains(label),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _items[i].labels.add(label);
                                } else {
                                  _items[i].labels.remove(label);
                                }
                              });
                            },
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(label),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
