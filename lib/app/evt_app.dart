import 'package:flutter/material.dart';

class EvtApp extends StatelessWidget {
  const EvtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('设备联调'),
        ),
      ),
    );
  }
}
