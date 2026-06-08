import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../common.dart';
import 'agent_dashboard_storage.dart';

AgentDashboardStorage createAgentDashboardStorage() {
  return FileAgentDashboardStorage();
}

class FileAgentDashboardStorage implements AgentDashboardStorage {
  @override
  Future<String> read(String peerId, String fileName) async {
    final file = await _storageFile(peerId, fileName);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String peerId, String fileName, String value) async {
    final file = await _storageFile(peerId, fileName);
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }

  Future<File> _storageFile(String peerId, String fileName) async {
    final baseDir = isAndroid || isIOS
        ? await getApplicationDocumentsDirectory()
        : await getApplicationSupportDirectory();
    final normalizedPeerId = peerId.isEmpty ? 'session' : peerId;
    return File(
      p.join(baseDir.path, 'agent-dashboard', '$normalizedPeerId-$fileName'),
    );
  }
}
