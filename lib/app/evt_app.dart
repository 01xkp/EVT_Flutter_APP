import 'package:evt_ble_app/core/design_system/evt_theme.dart';
import 'package:flutter/material.dart';

class EvtApp extends StatelessWidget {
  const EvtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: EvtTheme.light(),
      darkTheme: EvtTheme.dark(),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: const Center(
          child: Text('设备联调'),
        ),
      ),
    );
  }
}
