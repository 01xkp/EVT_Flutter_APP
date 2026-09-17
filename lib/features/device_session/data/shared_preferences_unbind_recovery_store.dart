import 'package:shared_preferences/shared_preferences.dart';

/// Stores only device identities and intent, never the six-byte security code.
class SharedPreferencesUnbindRecoveryStore {
  static const _key = 'dvt.unbind.pending_devices';
  Future<void> _tail = Future<void>.value();

  Future<bool> containsAny(Iterable<String> deviceKeys) async {
    await _tail;
    final preferences = await SharedPreferences.getInstance();
    final pending = preferences.getStringList(_key) ?? const <String>[];
    return deviceKeys.any(pending.contains);
  }

  Future<void> setPending(Iterable<String> deviceKeys, bool pending) {
    final keys = deviceKeys.toSet();
    final operation = _tail.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      final stored = (preferences.getStringList(_key) ?? <String>[]).toSet();
      if (pending) {
        stored.addAll(keys);
      } else {
        stored.removeAll(keys);
      }
      if (!await preferences.setStringList(_key, stored.toList()..sort())) {
        throw StateError('无法保存解绑恢复记录，请检查手机存储后重试。');
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}
