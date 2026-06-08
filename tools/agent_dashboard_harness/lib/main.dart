import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/agent_dashboard_dev_shell.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

const _mode =
    String.fromEnvironment('RUSTDESK_DEV_DASHBOARD_MODE', defaultValue: 'floating');
const _dataMode = String.fromEnvironment(
  'RUSTDESK_DEV_DASHBOARD_DATA_MODE',
  defaultValue: 'mock',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AgentDashboardHarnessApp());
}

class AgentDashboardHarnessApp extends StatelessWidget {
  const AgentDashboardHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    final botToastBuilder = BotToastInit();
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agent Dashboard Harness',
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      builder: (context, child) => botToastBuilder(context, child),
      home: AgentDashboardDevShell(
        mode: _mode.toLowerCase() == 'full'
            ? AgentDashboardDevMode.full
            : AgentDashboardDevMode.floating,
        useLiveBridge: _dataMode.toLowerCase() == 'live',
      ),
    );
  }
}
