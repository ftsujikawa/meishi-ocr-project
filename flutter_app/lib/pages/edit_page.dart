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
class _EditPageState extends State<EditPage> {
  bool _isUploading = false;
  String? _error;
  List<dynamic>? _blocks;
  final List<TextEditingController> _controllers = [];
  final List<double?> _confidences = [];
  final List<_FieldKind?> _kinds = [];
  final List<bool> _kindManuallySet = [];

  static final RegExp _emailRe = RegExp(
      r'([A-Z0-9._%+-]+)@([A-Z0-9.-]+)\.[A-Z]{2,}',
      caseSensitive: false);
  static final RegExp _urlRe =
      RegExp(r'\bhttps?://\S+|\bwww\.[^\s]+\b', caseSensitive: false);
  static final RegExp _faxHintRe =
      RegExp(r'\bFAX\b|ＦＡＸ|Fax', caseSensitive: false);
  static final RegExp _mobilePhoneRe =
      RegExp(r'(?:\+?81[-\s]?)?(?:0?7?0|0?8?0|0?9?0)[-\s]?\d{4}[-\s]?\d{4}');
  static final RegExp _landlinePhoneRe =
      RegExp(r'(?:\+?81[-\s]?)?0(?!70|80|90)\d{1,4}[-\s]?\d{1,4}[-\s]?\d{3,4}');
  static final RegExp _genericPhoneRe = RegExp(
      r'(?:\+?81[-\s]?)?(?:0\d{1,4}[-\s]?\d{1,4}[-\s]?\d{3,4}|\d{2,4}[-\s]?\d{2,4}[-\s]?\d{3,4})');
  static final RegExp _postalCodeRe = RegExp(r'(?:〒\s*)?\d{3}-?\d{4}');
  static final RegExp _addressRe = RegExp(r'(都|道|府|県|市|区|町|村|丁目|番地|号|ビル|階)');
  static final RegExp _nameRe = RegExp(
      r'^[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}A-Za-z\s]{2,}$',
      unicode: true);

  static final List<RegExp> _companyHints = [
    RegExp(
        r'(株式会社|（株）|\(株\)|有限会社|（有）|\(有\)|合同会社|LLC|Inc\.?|Co\.?|Ltd\.?|Corporation)',
        caseSensitive: false),
  ];

  static final List<RegExp> _titleHints = [
    RegExp(
        r'(代表取締役|取締役|社長|副社長|専務|常務|部長|次長|課長|主任|係長|マネージャ|リーダー|Engineer|Manager|Director|CEO|COO|CTO|CFO)',
        caseSensitive: false),
  ];

  static final List<RegExp> _affiliationHints = [
    RegExp(r'(本部|部|課|室|局|支店|営業所|グループ|チーム|センター|研究所|Div\.?|Dept\.?|Department)',
        caseSensitive: false),
  ];

  _FieldKind? _classify(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;

    if (_emailRe.hasMatch(t)) return _FieldKind.email;
    if (_urlRe.hasMatch(t)) return _FieldKind.url;
    if (_postalCodeRe.hasMatch(t)) return _FieldKind.postalCode;
    if (_addressRe.hasMatch(t)) return _FieldKind.address;

    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 9 && _genericPhoneRe.hasMatch(t)) {
      if (_faxHintRe.hasMatch(t)) return _FieldKind.fax;
      if (_mobilePhoneRe.hasMatch(t)) return _FieldKind.mobilePhone;
      if (_landlinePhoneRe.hasMatch(t)) return _FieldKind.landlinePhone;
      return _FieldKind.landlinePhone;
    }

    if (_titleHints.any((r) => r.hasMatch(t))) return _FieldKind.title;
    if (_affiliationHints.any((r) => r.hasMatch(t))) {
      return _FieldKind.affiliation;
    }
    if (_companyHints.any((r) => r.hasMatch(t))) return _FieldKind.company;

    if (_nameRe.hasMatch(t) && !t.contains(RegExp(r'\d'))) {
      return _FieldKind.name;
    }

    return null;
  }

  String _normalizePostalCode(String input) {
    final t = input.trim();
    if (t.isEmpty) return t;
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 7) {
      return '〒${digits.substring(0, 3)}-${digits.substring(3)}';
    }
    if (t.startsWith('〒')) return t;
    return '〒$t';
  }

  String _csvEscape(String v) {
    final s = v.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final needsQuote = s.contains(',') || s.contains('"') || s.contains('\n');
    final escaped = s.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  String _buildCsv() {
    String? company;
    String? affiliation;
    String? title;
    String? name;
    String? address;
    String? postalCode;

    final landlines = <String>[];
    final mobiles = <String>[];
    final faxes = <String>[];
    final emails = <String>[];
    final urls = <String>[];

    for (var i = 0; i < _controllers.length; i++) {
      final text = _controllers[i].text.trim();
      if (text.isEmpty) continue;
      final kind = (i < _kinds.length) ? _kinds[i] : null;

      switch (kind) {
        case _FieldKind.company:
          company ??= text;
          break;
        case _FieldKind.affiliation:
          affiliation ??= text;
          break;
        case _FieldKind.title:
          title ??= text;
          break;
        case _FieldKind.name:
          name ??= text;
          break;
        case _FieldKind.landlinePhone:
          landlines.add(text);
          break;
        case _FieldKind.mobilePhone:
          mobiles.add(text);
          break;
        case _FieldKind.fax:
          faxes.add(text);
          break;
        case _FieldKind.email:
          emails.add(text);
          break;
        case _FieldKind.url:
          urls.add(text);
          break;
        case _FieldKind.postalCode:
          postalCode ??= _normalizePostalCode(text);
          break;
        case _FieldKind.address:
          address ??= text;
          break;
        case null:
          break;
      }
    }

    const header = [
      '会社名',
      '所属',
      '役職',
      '氏名',
      '固定電話',
      '携帯電話',
      'FAX',
      'E-mail',
      'URL',
      '郵便番号',
      '住所',
    ];

    final row = [
      company ?? '',
      affiliation ?? '',
      title ?? '',
      name ?? '',
      landlines.join(' / '),
      mobiles.join(' / '),
      faxes.join(' / '),
      emails.join(' / '),
      urls.join(' / '),
      postalCode ?? '',
      address ?? '',
    ];

    return '${header.map(_csvEscape).join(',')}\n'
        '${row.map(_csvEscape).join(',')}\n';
  }

  Future<void> _exportCsv() async {
    final csv = _buildCsv();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('CSV出力'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(csv),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: csv));
                if (!context.mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('CSVをコピーしました')),
                );
              },
              child: const Text('コピー'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  String _labelForKind(_FieldKind? kind) {
    switch (kind) {
      case _FieldKind.company:
        return '会社名';
      case _FieldKind.title:
        return '役職';
      case _FieldKind.affiliation:
        return '所属';
      case _FieldKind.name:
        return '氏名';
      case _FieldKind.landlinePhone:
        return '固定電話';
      case _FieldKind.mobilePhone:
        return '携帯電話';
      case _FieldKind.fax:
        return 'FAX';
      case _FieldKind.email:
        return 'E-mail';
      case _FieldKind.url:
        return 'URL';
      case _FieldKind.postalCode:
        return '郵便番号';
      case _FieldKind.address:
        return '住所';
      case null:
        return '未分類';
    }
  }

  Widget _classificationCheckboxesForIndex(
    BuildContext context, {
    required int index,
  }) {
    final current = (index < _kinds.length) ? _kinds[index] : null;

    const kinds = <_FieldKind>[
      _FieldKind.company,
      _FieldKind.affiliation,
      _FieldKind.title,
      _FieldKind.name,
      _FieldKind.landlinePhone,
      _FieldKind.mobilePhone,
      _FieldKind.fax,
      _FieldKind.email,
      _FieldKind.url,
      _FieldKind.postalCode,
      _FieldKind.address,
    ];

    void setKind(_FieldKind? k) {
      if (index >= _kinds.length) return;
      setState(() {
        _kinds[index] = k;
        if (index < _kindManuallySet.length) {
          _kindManuallySet[index] = true;
        }
      });

      if (k == _FieldKind.postalCode && index < _controllers.length) {
        final normalized = _normalizePostalCode(_controllers[index].text);
        if (_controllers[index].text != normalized) {
          _controllers[index].text = normalized;
          _controllers[index].selection = TextSelection.collapsed(
            offset: normalized.length,
          );
        }
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in kinds)
          FilterChip(
            label: Text(_labelForKind(k)),
            selected: current == k,
            onSelected: (selected) {
              if (!selected) return;
              setKind(k);
            },
            showCheckmark: true,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        FilterChip(
          label: Text(_labelForKind(null)),
          selected: current == null,
          onSelected: (selected) {
            if (!selected) return;
            setKind(null);
          },
          showCheckmark: true,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Color _tintForConfidence(BuildContext context, double? confidence) {
    final scheme = Theme.of(context).colorScheme;
    if (confidence == null) {
      return scheme.surfaceContainerHighest;
    }

    final c = confidence.clamp(0.0, 1.0);
    // Low confidence => errorContainer, High confidence => primaryContainer
    final base =
        Color.lerp(scheme.errorContainer, scheme.primaryContainer, c) ??
            scheme.surfaceContainerHighest;
    return base;
  }

  void _setEditableBlocks(List<dynamic> blocks) {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
    _confidences.clear();
    _kinds.clear();
    _kindManuallySet.clear();

    for (final b in blocks) {
      final text =
          (b is Map && b['text'] != null) ? b['text'].toString() : b.toString();
      final conf = (b is Map && b['confidence'] is num)
          ? (b['confidence'] as num).toDouble()
          : null;
      _controllers.add(TextEditingController(text: text));
      _confidences.add(conf);
      _kinds.add(_classify(text));
      _kindManuallySet.add(false);
    }

    _blocks = blocks;
  }

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
        _setEditableBlocks(blocks);
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

  void _done() {
    final edited = <Map<String, dynamic>>[];
    for (var i = 0; i < _controllers.length; i++) {
      edited.add({
        'text': _controllers[i].text,
        'confidence': _confidences[i],
        'kind': _kinds[i]?.name,
      });
    }
    Navigator.of(context).pop(edited);
  }

  Future<void> _saveToContacts() async {
    if (_controllers.isEmpty) return;

    final ok = await FlutterContacts.requestPermission();
    if (!ok) {
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
    String? company;
    String? affiliation;
    String? title;
    String? name;
    String? address;
    String? postalCode;

    final landlines = <String>[];
    final mobiles = <String>[];
    final faxes = <String>[];
    final emails = <String>[];
    final urls = <String>[];

    for (var i = 0; i < _controllers.length; i++) {
      final text = _controllers[i].text.trim();
      if (text.isEmpty) continue;
      final kind = (i < _kinds.length) ? _kinds[i] : null;

      switch (kind) {
        case _FieldKind.company:
          company ??= text;
          break;
        case _FieldKind.title:
          title ??= text;
          break;
        case _FieldKind.affiliation:
          affiliation ??= text;
          break;
        case _FieldKind.name:
          name ??= text;
          break;
        case _FieldKind.landlinePhone:
          landlines.add(text);
          break;
        case _FieldKind.mobilePhone:
          mobiles.add(text);
          break;
        case _FieldKind.fax:
          faxes.add(text);
          break;
        case _FieldKind.email:
          emails.add(text);
          break;
        case _FieldKind.url:
          urls.add(text);
          break;
        case _FieldKind.address:
          address ??= text;
          break;
        case _FieldKind.postalCode:
          postalCode ??= _normalizePostalCode(text);
          break;
        case null:
          break;
      }
    }

    final fullName = (name == null || name.trim().isEmpty) ? '名刺' : name.trim();

    final contact = Contact();
    contact.name.first = fullName;

    if (company != null || title != null) {
      final mergedTitle = [
        if (title != null && title.trim().isNotEmpty) title.trim(),
        if (affiliation != null && affiliation.trim().isNotEmpty)
          affiliation.trim(),
      ].join(' / ');

      contact.organizations = [
        Organization(
          company: company ?? '',
          title: mergedTitle,
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
    final needsQuote = v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r');
    final escaped = v.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
    contact.phones = [
      for (final p in landlines) Phone(p, label: PhoneLabel.work),
      for (final p in mobiles) Phone(p, label: PhoneLabel.mobile),
      for (final p in faxes) Phone(p, label: PhoneLabel.faxWork),
    ];

    contact.emails = [
      for (final e in emails) Email(e, label: EmailLabel.work),
    ];

    contact.websites = [
      for (final u in urls) Website(u, label: WebsiteLabel.work),
    ];

    final street = [
      if (postalCode != null) postalCode,
      if (address != null) address,
    ].whereType<String>().join(' ');

    if (street.isNotEmpty) {
      contact.addresses = [
        Address(street, label: AddressLabel.work),
      ];
    }

    await contact.insert();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('連絡先に保存しました')),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
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
                          Text(
                              'conf: ${_items[i].confidence!.toStringAsFixed(2)}'),
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
        title: const Text('編集'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              FilledButton.icon(
                onPressed: _isUploading ? null : _runOcr,
                icon: _isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isUploading ? 'OCR中...' : 'OCR'),
              ),
              FilledButton.tonal(
                onPressed: _blocks == null
                    ? null
                    : () {
                        _exportCsv();
                      },
                child: const Text('CSV'),
              ),
              FilledButton.tonal(
                onPressed: _blocks == null ? null : _saveToContacts,
                child: const Text('電話帳'),
              ),
              FilledButton(
                onPressed: _blocks == null ? null : _done,
                child: const Text('完了'),
              ),
            ],
          ),
        ),
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
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
                    final conf = (index < _confidences.length)
                        ? _confidences[index]
                        : null;
                    final subtitle = conf == null
                        ? null
                        : 'confidence: ${conf.toStringAsFixed(2)}';

                    final tint = _tintForConfidence(context, conf);

                    return Card(
                      color: tint,
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _classificationCheckboxesForIndex(
                                context,
                                index: index,
                              ),
                            ),
                            TextField(
                              controller: _controllers[index],
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor:
                                    Theme.of(context).colorScheme.surface,
                                border: const OutlineInputBorder(),
                                labelText: '項目 ${index + 1}',
                                helperText: subtitle,
                              ),
                              minLines: 1,
                              maxLines: 3,
                              onChanged: (value) {
                                if (index >= _kinds.length) return;
                                if (value.trim().isEmpty) {
                                  setState(() {
                                    _kinds[index] = null;
                                    if (index < _kindManuallySet.length) {
                                      _kindManuallySet[index] = false;
                                    }
                                  });
                                  return;
                                }

                                final isManual =
                                    (index < _kindManuallySet.length)
                                        ? _kindManuallySet[index]
                                        : false;
                                if (isManual) return;

                                final next = _classify(value);
                                if (_kinds[index] == next) return;
                                setState(() {
                                  _kinds[index] = next;
                                });
                              },
                            ),
                          ],
                        ),
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

enum _FieldKind {
  company,
  affiliation,
  title,
  name,
  landlinePhone,
  mobilePhone,
  fax,
  email,
  url,
  postalCode,
  address,
}
