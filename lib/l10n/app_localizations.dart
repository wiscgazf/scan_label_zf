import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class LocaleController extends ChangeNotifier {
  Locale _locale = const Locale('zh');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (!AppLocalizations.supportedLocales.contains(locale) ||
        _locale == locale) {
      return;
    }
    _locale = locale;
    notifyListeners();
  }
}

final appLocaleController = LocaleController();

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('zh')];
  static const delegate = _AppLocalizationsDelegate();
  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    assert(localizations != null, 'AppLocalizations is missing from the app.');
    return localizations!;
  }

  String _text(String en, String zh) => locale.languageCode == 'zh' ? zh : en;

  String get appTitle => _text('Label Scan', '标签扫一扫');
  String get manage => _text('Manage', '管理');
  String get language => _text('Language', '语言');
  String get selectLanguage => _text('Select language', '选择语言');
  String get scan => _text('Scan', '扫一扫');
  String get chooseFile => _text('Recognize from file', '选择文件识别');
  String get offlineReady => _text('Offline ready', '离线就绪');
  String get workflowPosition => _text('Position', '扫码定位');
  String get workflowOcr => _text('OCR', 'OCR 识别');
  String get workflowReview => _text('Review & save', '核对保存');
  String get recentScan => _text('Recent scan', '最近扫描');
  String get unnamedMaterial => _text('No material name', '未填写物料名称');
  String get rawKey => _text('Original key', '原始 Key');
  String get fieldsConfirmed => _text('Label details confirmed', '标签字段已确认');

  String get reviewTitle => _text('Review label details', '核对标签信息');
  String get coreInfo => _text('Core material details', '核心物料信息');
  String get supplyInventory => _text('Supply & inventory', '供应与库存');
  String get orderBatch => _text('Order & batch', '订单与批次');
  String get rawQrContent => _text('Original QR content', '二维码原始内容');
  String get cancel => _text('Cancel', '取消');
  String get confirm => _text('Confirm', '确认');
  String get done => _text('Done', '确定');

  String get recommendedLocation => _text('Recommended location', '推荐仓位');
  String get materialCode => _text('Material code', '物料编码');
  String get name => _text('Name', '名称');
  String get specification => _text('Specification', '产品规格');
  String get supplier => _text('Supplier', '供应商');
  String get quantity => _text('Quantity', '数量');
  String get orderNumber => _text('Order number', '订单号');
  String get cartonCount => _text('Carton count', '整箱总数');
  String get productionBatch => _text('Production batch', '生产批次');
  String get deliveryDate => _text('Delivery date', '送货日期');

  String inputHint(String label) => _text('Enter $label', '请输入$label');
  String missingField(String label) => _text(
    'No $label detected. Please enter it manually.',
    '未识别到$label，请手动填写',
  );

  String get scanLabel => _text('Scan label', '扫描标签');
  String get toggleTorch => _text('Toggle flashlight', '切换闪光灯');
  String get switchCamera => _text('Switch camera', '切换摄像头');
  String recognitionFailed(Object error) =>
      _text('Recognition failed: $error', '识别失败：$error');
  String get imagePathMissing => _text(
    'No image path available. Please select the image again.',
    '未获取到图片路径，请重新选择',
  );
  String get qrNotFound => _text(
    'No QR code found. Please select a clear label image.',
    '所选图片中未识别到二维码，请选择清晰的标签图片',
  );
  String get selectLabelImage => _text('Select label image', '选择标签图片');
  String filePickFailed(Object error) =>
      _text('Could not select file: $error', '选择文件失败：$error');
  String get imageRecognitionUnsupported => _text(
    'Image recognition is not supported on this device',
    '当前设备不支持选择图片识别',
  );
  String imageRecognitionFailed(Object error) =>
      _text('Image recognition failed: $error', '图片识别失败：$error');
  String get timedCaptureHint =>
      _text('QR code detected. Capturing shortly…', '已识别二维码，即将自动拍摄…');
  String get steadyCaptureHint => _text(
    'Hold steady to capture automatically, or tap Recognize now.',
    '请持稳手机，稳定后自动拍摄，也可点击立即识别',
  );
  String get positionHint => _text(
    'Place the entire label in the frame, or select an image above.',
    '将标签完整置于取景框内，也可点击右上角选择标签图片',
  );
  String get qrLocated => _text('QR code located', '二维码已定位');
  String get alignQr => _text('Align QR code', '对准标签二维码');
  String get processing => _text('Recognizing label details…', '正在识别标签字段…');
  String get recognizeNow => _text('Recognize now', '立即识别');

  String get recordsTitle => _text('Label records', '标签管理');
  String get dateFilter => _text('Date filter', '日期筛选');
  String get editDateFilter => _text('Edit date filter', '修改日期筛选');
  String get clearDateFilter => _text('Clear date filter', '清除日期筛选');
  String get deleteRecordTitle => _text('Delete record', '删除记录');
  String deleteRecordMessage(String name) =>
      _text('Delete the label record for "$name"?', '确定删除「$name」这条标签记录吗？');
  String get delete => _text('Delete', '删除');
  String get all => _text('All', '全部');
  String get duplicates => _text('Duplicates', '重复标签');
  String get searchHint => _text('Search name or code', '搜索物料名称或编码');
  String get selectDateRange =>
      _text('Select recording date range', '选择录入日期区间');
  String get selectStartDate => _text('Select a start date', '请选择开始日期');
  String get selectEndDate => _text('Select an end date', '请选择结束日期');
  String get dateRangeTo => _text('to', '至');
  String get previousMonth => _text('Previous month', '上一个月');
  String get nextMonth => _text('Next month', '下一个月');

  List<String> get weekdays => locale.languageCode == 'zh'
      ? const ['一', '二', '三', '四', '五', '六', '日']
      : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String monthTitle(DateTime month) {
    if (locale.languageCode == 'zh') {
      return '${month.year}年 ${month.month}月';
    }
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[month.month - 1]} ${month.year}';
  }

  String get emptyFiltered => _text('No matching records', '没有符合条件的记录');
  String get emptyRecords => _text(
    'No label records yet. Scan a label to get started.',
    '暂无标签记录，先去首页扫一扫',
  );
  String get emptyFilteredDuplicates =>
      _text('No matching duplicate records', '没有符合条件的重复记录');
  String get emptyDuplicates =>
      _text('No records with duplicate codes', '没有重复编码的记录');
  String get noMore => _text('No more records', '没有更多了');
  String duplicateCount(int count) => _text('$count duplicates', '重复 $count 次');
  String get unnamedRecord => _text('(No name)', '（未填写名称）');
  String codeLabel(String code) => _text('Code: $code', '编码：$code');
  String get edit => _text('Edit', '编辑');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.contains(Locale(locale.languageCode));

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(Locale(locale.languageCode)));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
