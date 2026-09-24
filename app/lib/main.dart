import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'api/api_config.dart';
import 'api/health_api.dart';
import 'ui/health_check_screen.dart';

void main() {
  final dio = Dio(BaseOptions(
    baseUrl: apiBaseUrl,
    // A Python function that has scaled to zero takes a few seconds to
    // start (the free tier keeps min instances at 0), so allow for it.
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));
  runApp(FitnessApp(healthApi: HealthApi(dio)));
}

class FitnessApp extends StatelessWidget {
  const FitnessApp({super.key, required this.healthApi});

  final HealthApi healthApi;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fitness',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: HealthCheckScreen(checkStatus: healthApi.status, apiBaseUrl: apiBaseUrl),
    );
  }
}
