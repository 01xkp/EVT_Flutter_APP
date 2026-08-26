import 'package:aipin/app/evt_app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ProviderScope(child: EvtApp()));
}
