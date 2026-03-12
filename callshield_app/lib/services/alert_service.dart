import 'dart:async';
import 'dart:convert';
import 'dart:io'; // 🚨 NEW: Required for raw WebSocket headers
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart'; // 🚨 NEW: Upgraded channel
import 'package:web_socket_channel/web_socket_channel.dart';

class AlertService {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _alertController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get alertStream => _alertController.stream;

  bool isMonitoring = true;
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);

  String? _currentUrl;
  Timer? _reconnectTimer;

  int _retryDelaySeconds = 3;
  final int _maxRetryDelay = 60;

  void connect(String url) {
    _currentUrl = url;
    _initConnection();
  }

  // 🚨 NEW: Made this async to await the custom header connection
  Future<void> _initConnection() async {
    if (_currentUrl == null) return;

    try {
      final wsUrlString = _currentUrl!.startsWith('http')
          ? _currentUrl!.replaceFirst('http', 'ws')
          : _currentUrl!;

      // 🚨 THE FIX: Force Ngrok to skip the HTML warning page
      final ws = await WebSocket.connect(
        wsUrlString,
        headers: {
          "ngrok-skip-browser-warning": "69420", // The magic bypass key
        },
      );

      // Wrap the connected raw socket in our channel
      _channel = IOWebSocketChannel(ws);

      isConnected.value = true;
      _retryDelaySeconds = 3;
      print("✅ [AlertService] Connected to backend");

      _channel!.stream.listen(
            (message) {
          try {
            final data = json.decode(message);
            _alertController.add(data);
          } catch (e) {
            print("Error parsing message: $e");
          }
        },
        onDone: () {
          print("❌ [AlertService] WebSocket Disconnected (Server offline)");
          _handleDisconnect();
        },
        onError: (error) {
          print("❌ [AlertService] WebSocket Error: $error");
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print("❌ [AlertService] Connection failed (Ngrok blocking or Server off): $e");
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    isConnected.value = false;
    _channel?.sink.close();
    _channel = null;

    _reconnectTimer?.cancel();

    print("🔄 [AlertService] Backend offline. Next retry in $_retryDelaySeconds seconds...");

    _reconnectTimer = Timer(Duration(seconds: _retryDelaySeconds), () {
      if (!isConnected.value) {
        _initConnection();
        _retryDelaySeconds = (_retryDelaySeconds * 2).clamp(3, _maxRetryDelay);
      }
    });
  }

  void toggleMonitoring() {
    isMonitoring = !isMonitoring;
    if (_channel != null && isConnected.value) {
      final action = isMonitoring ? 'resume_monitoring' : 'pause_monitoring';
      _channel!.sink.add(jsonEncode({'action': action}));
      print("Sent to Backend: $action");
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    isConnected.value = false;
  }
}