import 'package:connectivity_plus/connectivity_plus.dart';

import 'offline_storage_service.dart';

class SyncManagerService {
  final OfflineStorageService _storageService = OfflineStorageService();

  // Check internet and sync pending offline recordings
  Future<void> syncOfflineDataToServer() async {
    // Check if internet is available
    final connectivityResult = await Connectivity().checkConnectivity();

    if (!connectivityResult.contains(ConnectivityResult.none)) {
      // Get all unsynced local records from internal memory
      List<Map<String, dynamic>> unsyncedList =
          await _storageService.getUnsyncedData();

      for (var record in unsyncedList) {
        String filePath = record['path'];
        dynamic key = record['key'];

        // Simulate sending to server/parent device
        bool uploadSuccess = await _uploadToServer(filePath);

        // If successfully uploaded, delete from internal memory
        if (uploadSuccess) {
          await _storageService.deleteSyncedData(key);
        }
      }
    }
  }

  Future<bool> _uploadToServer(String filePath) async {
    // Implement actual server upload logic here (WebRTC / HTTP POST)
    await Future.delayed(const Duration(seconds: 1)); // Simulation
    return true;
  }
}
