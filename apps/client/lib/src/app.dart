import 'package:flutter/material.dart';

import 'home_screen.dart';

class OpenCloudApp extends StatelessWidget {
  const OpenCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open UCloud',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176C72),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      home: const HomeScreen(),
    );
  }
}
