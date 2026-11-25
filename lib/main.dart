import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'pages/label_scan/label_records.dart';
import 'pages/label_scan/label_records_page.dart';
import 'pages/label_scan/label_scan_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时打开本地数据库，避免首次进入管理页等待建库。
  await labelRecordStore.open();
  runApp(const MyApp());
}

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const LabelScanPage()),
    GoRoute(
      path: '/records',
      builder: (context, state) => const LabelRecordsPage(),
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '标签扫一扫',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      routerConfig: _router,
    );
  }
}
