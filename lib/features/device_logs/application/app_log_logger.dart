import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_logs/domain/app_log_store.dart';

/// Bridges the app-wide diagnostic contract to the persistent debug log.
class PersistentAppLogger implements SafeAppLogger {
  const PersistentAppLogger(this._store, {this.scope = 'APP'});

  final AppLogStore _store;
  final String scope;

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {
    _store.info(event, scope: scope, fields: fields);
  }
}
