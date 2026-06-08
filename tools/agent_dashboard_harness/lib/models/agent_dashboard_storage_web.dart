// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'agent_dashboard_storage.dart';

AgentDashboardStorage createAgentDashboardStorage() {
  return WebAgentDashboardStorage();
}

class WebAgentDashboardStorage implements AgentDashboardStorage {
  static const _prefix = 'rustdesk-agent-dashboard';

  @override
  Future<String> read(String peerId, String fileName) async {
    return html.window.localStorage[_key(peerId, fileName)] ?? '';
  }

  @override
  Future<void> write(String peerId, String fileName, String value) async {
    html.window.localStorage[_key(peerId, fileName)] = value;
  }

  String _key(String peerId, String fileName) {
    final normalizedPeerId = peerId.isEmpty ? 'session' : peerId;
    return '$_prefix:$normalizedPeerId:$fileName';
  }
}
