abstract class AgentDashboardStorage {
  Future<String> read(String peerId, String fileName);

  Future<void> write(String peerId, String fileName, String value);
}
