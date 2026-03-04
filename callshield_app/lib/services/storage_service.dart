import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _alertsKey = 'callshield_alerts_history';

  // Save a new alert to local storage
  Future<void> saveAlert(Map<String, dynamic> alertPayload) async {
    final prefs = await SharedPreferences.getInstance();

    // Get existing alerts
    List<String> savedAlerts = prefs.getStringList(_alertsKey) ?? [];

    // Add a timestamp to the alert so we know when it happened
    alertPayload['timestamp'] = DateTime.now().toIso8601String();

    // Add the new alert to the beginning of the list
    savedAlerts.insert(0, json.encode(alertPayload));

    // Save it back to the device
    await prefs.setStringList(_alertsKey, savedAlerts);
  }

  // Retrieve all saved alerts
  Future<List<Map<String, dynamic>>> getAlertHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedAlerts = prefs.getStringList(_alertsKey) ?? [];

    // Convert the saved JSON strings back into Maps
    return savedAlerts.map((alertString) =>
    json.decode(alertString) as Map<String, dynamic>
    ).toList();
  }

  // Clear history (Useful for a "Delete All" button)
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_alertsKey);
  }
}