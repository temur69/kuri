import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

enum OrderState { pending, accepted, onWay, delivered, canceled }

class OrderModel {
  final String id;
  final String customerName;
  final String customerPhone;
  final String pickupAddress;
  final String dropoffAddress;
  final double distanceKm;
  final double totalPrice;
  final double courierEarnings;
  final String pinCode;
  OrderState state;

  OrderModel({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.totalPrice,
    required this.courierEarnings,
    required this.pinCode,
    this.state = OrderState.pending,
  });
}

class SystemConfig {
  static double baseFee = 50.0;
  static double perKmFee = 20.0;
  static double commissionRate = 15.0;
  static String adminPin = "1923";
  static bool nightMode = false;
}

class SystemEngine {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static bool isAlarmPlaying = false;

  static Future<void> initNotificationService() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notificationsPlugin.initialize(const InitializationSettings(android: androidSettings));

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'kurye_alarm_channel',
      'Kurye Çağrı Kanalı',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  static Future<void> startOrderAlarm(String orderId, double price) async {
    isAlarmPlaying = true;
    try {
      await _audioPlayer.play(UrlSource('https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3'));
    } catch (_) {}

    const androidDetails = AndroidNotificationDetails(
      'kurye_alarm_channel',
      'Kurye Çağrı Kanalı',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      ticker: 'Yeni Paket Geldi!',
    );

    await _notificationsPlugin.show(
      1001,
      '🚨 YENİ SİPARİŞ GELDİ! ($price ₺)',
      'Paket kabul bekliyor. Hemen inceleyin!',
      const NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> stopOrderAlarm() async {
    isAlarmPlaying = false;
    await _audioPlayer.stop();
    await _notificationsPlugin.cancel(1001);
  }

  static Future<Map<String, dynamic>> resolveLocation(String input) async {
    input = input.trim();
    final regex = RegExp(r'q=([0-9.-]+),([0-9.-]+)');
    final match = regex.firstMatch(input);

    if (match != null) {
      return {'lat': double.parse(match.group(1)!), 'lng': double.parse(match.group(2)!)};
    }

    if (input.startsWith('http://') || input.startsWith('https://')) {
      try {
        final client = http.Client();
        final req = http.Request('GET', Uri.parse(input))..followRedirects = false;
        final res = await client.send(req);
        final redirectUrl = res.headers['location'] ?? input;
        final resMatch = regex.firstMatch(redirectUrl);
        if (resMatch != null) {
          return {'lat': double.parse(resMatch.group(1)!), 'lng': double.parse(resMatch.group(2)!)};
        }
      } catch (_) {}
    }

    return {'lat': 41.0082, 'lng': 28.9784};
  }

  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    double direct = 12742 * asin(sqrt(a));
    return double.parse((direct * 1.25).toStringAsFixed(1));
  }

  static double computePrice(double km) {
    double total = SystemConfig.baseFee + (km * SystemConfig.perKmFee);
    if (SystemConfig.nightMode) total *= 1.25;
    return double.parse(total.toStringAsFixed(2));
  }

  static double computeCourierShare(double total) {
    double payout = total * ((100 - SystemConfig.commissionRate) / 100);
    return double.parse(payout.toStringAsFixed(2));
  }
}
