import 'dart:convert';

import 'diagnostic_sanitizer.dart';
import 'diagnostic_trace.dart';

enum DiagnosticLevel { info, warning, error }

/// Immutable, sanitized event shared by the debug viewer and every log sink.
class DiagnosticEvent {
  DiagnosticEvent({
    required this.timestamp,
    required this.level,
    required String scope,
    required String event,
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    this.elapsed,
    Map<String, Object?> fields = const {},
    DiagnosticSanitizer sanitizer = const DiagnosticSanitizer(),
  }) : scope = sanitizer.normalizeScope(scope),
       traceId = sanitizer.normalizeTraceId(trace?.traceId),
       trace = trace == null
           ? null
           : DiagnosticTrace.sanitized(
               source: trace,
               traceId: sanitizer.normalizeTraceId(trace.traceId),
               operation: sanitizer.normalizeOperation(
                 operation ?? trace.operation,
               ),
             ),
       operation = sanitizer.normalizeOperation(operation ?? trace?.operation),
       stage = sanitizer.normalizeStage(stage),
       event = sanitizer.normalizeEvent(event),
       result = sanitizer.normalizeResult(result),
       fields = sanitizer.sanitize(
         scope: sanitizer.normalizeScope(scope),
         fields: fields,
       );

  final DateTime timestamp;
  final DiagnosticLevel level;
  final String scope;
  final DiagnosticTrace? trace;
  final String traceId;
  final String operation;
  final String stage;
  final String event;
  final String result;
  final Duration? elapsed;
  final Map<String, Object?> fields;

  String get effectiveOperation => operation;

  /// Stable human-readable marker for Android/iOS debug logs and log files.
  ///
  /// The structured fields emitted after this marker remain intentionally
  /// English and machine-readable for filtering and support tooling.
  String get chineseLogPrefix {
    // Keep the first three segments stable: field engineers already search
    // Logcat/Xcode and exported files with this prefix. Stage and action make
    // each individual line understandable without needing an event glossary.
    return '【AIPIN联调】【${_chineseScopeLabel(scope)}】'
        '${_chineseProtocolDirectionPrefix(event, stage)}'
        '【${_chineseLevelLabel(level)}】'
        '【阶段：${_chineseStageLabel(stage)}】'
        '【动作：${_chineseEventLabel(event)}】';
  }

  /// Makes the physical GATT direction immediately visible while retaining the
  /// stable, machine-readable event identifier after the prefix.
  String _chineseProtocolDirectionPrefix(String event, String stage) {
    return switch (event) {
      'evt_command_queued' => '【发送：等待写入设备】',
      'evt_command_transmit_started' ||
      'evt_command_transmit_completed' => '【发送：App到设备】',
      'evt_stream_command_queued' => '【发送：等待写入设备】',
      'evt_stream_command_transmit_started' ||
      'evt_stream_command_transmit_completed' => '【发送：App到设备】',
      'write_requested' ||
      'write_native_invoked' ||
      'write_completed' ||
      'write_failed' ||
      'write_without_response_requested' ||
      'write_without_response_native_invoked' ||
      'write_without_response_completed' ||
      'write_without_response_failed' => '【发送：App到设备】',
      'read_requested' => '【读取：App到设备】',
      'evt_command_frame_decoded' ||
      'evt_command_response_received' ||
      'evt_command_response_matched' ||
      'evt_command_response_unmatched' ||
      'evt_command_completed' ||
      'evt_stream_command_completed' ||
      'notification_received' ||
      'read_completed' => '【接收：设备到App】',
      'evt_command_response_decode_failed' ||
      'evt_command_response_match_failed' ||
      'evt_stream_command_error' ||
      'notification_frame_decode_failed' ||
      'notification_endpoint_mismatch' => '【接收：设备到App】【异常：回包处理】',
      'evt_command_timeout' || 'evt_stream_command_timeout' => '【等待：设备响应】',
      'evt_response_wait_started' ||
      'evt_response_wait_armed' ||
      'evt_response_waiting' ||
      'evt_response_wait_finished' => '【回包监听：等待设备响应】',
      'evt_command_error' when stage == 'write' => '【发送：App到设备】【异常：写入失败】',
      'evt_command_error' => '【等待：设备响应】【异常：命令处理】',
      _ => '',
    };
  }

  DiagnosticEvent copyWith({Map<String, Object?>? fields}) {
    return DiagnosticEvent(
      timestamp: timestamp,
      level: level,
      scope: scope,
      trace: trace,
      operation: operation,
      stage: stage,
      event: event,
      result: result,
      elapsed: elapsed,
      fields: fields ?? this.fields,
    );
  }

  String formatLine() {
    final normalizedFields = fields.entries
        .map((entry) => '${entry.key}=${_formatValue(entry.value)}')
        .join(' ');
    final parts = <String>[
      timestamp.toUtc().toIso8601String(),
      level.name.toUpperCase(),
      scope,
      traceId,
      effectiveOperation,
      stage,
      event,
      result,
      elapsed?.inMilliseconds.toString() ?? '-',
    ];
    if (normalizedFields.isNotEmpty) {
      parts.add(normalizedFields);
    }
    return '$chineseLogPrefix ${parts.join(' | ')}';
  }

  String _chineseScopeLabel(String value) {
    return switch (value) {
      'AI' => 'AI服务',
      'APP' => '应用',
      'APP_LIFECYCLE' => '应用生命周期',
      'AUDIO' => '音频',
      'AUTH' => '认证',
      'BLE' => '蓝牙',
      'CMD' => '协议',
      'DEVICE_API' => '设备接口',
      'EXPORT' => '导出',
      'FILE' => '文件',
      'DVT_FILE' => 'DVT文件',
      'DVT_ARCHIVE' || 'ARCHIVE' => 'DVT归档',
      'RECONNECT' => '回连',
      'SESSION' => '会话',
      'SESSION_FLOW' => '会话流程',
      'STORAGE' => '存储',
      'UI' => '界面',
      _ => '应用',
    };
  }

  String _chineseLevelLabel(DiagnosticLevel value) {
    return switch (value) {
      DiagnosticLevel.info => '信息',
      DiagnosticLevel.warning => '警告',
      DiagnosticLevel.error => '错误',
    };
  }

  String _chineseStageLabel(String value) {
    return switch (value) {
      'archive' => '归档处理',
      'checkpoint' => '本地断点',
      'metadata' => '读取元数据',
      'transfer' => '文件传输',
      'verification' || 'local_verification' => '完整性校验',
      'cloud_upload' => '云端上传',
      'device_confirmation' => '设备确认',
      'cleanup' => '清理',
      'challenge' => '认证挑战',
      'connect' => '蓝牙连接',
      'download' => '文件下载',
      'export' => '文件导出',
      'fa19_write' => '认证特征写入',
      'import' => '文件导入',
      'initialization' => '初始化',
      'read' => '特征读取',
      'request' => '请求准备',
      'response' => '回包处理',
      'sync' => '状态同步',
      'ticket_request' => '认证票据请求',
      'upload' => '上传处理',
      'validation' => '数据校验',
      'write' => '协议写入',
      'idle' => '资源关闭',
      'scanning' => '设备扫描',
      'connecting' => '建立连接',
      'waiting_to_retry' => '等待回连',
      'connected' => '连接保持',
      'exhausted' => '重试耗尽',
      'suppressed' => '回连抑制',
      _ => '未分阶段',
    };
  }

  /// Event identifiers intentionally remain English and machine-readable in
  /// the structured portion of a line. This lightweight mapping gives their
  /// common EVT lifecycle vocabulary a stable Chinese marker for field logs.
  String _chineseEventLabel(String value) {
    if (value == 'unknown_event') {
      return '未知事件';
    }
    final tokens = value.split('_');
    final labels = <String>[];
    for (final token in tokens) {
      final label = _chineseEventTokenLabel(token);
      if (label == null) {
        return _fallbackChineseEventLabel(value);
      }
      labels.add(label);
    }
    return labels.isEmpty ? '流程事件' : labels.join();
  }

  String _fallbackChineseEventLabel(String value) {
    if (value.endsWith('_requested')) {
      return '流程请求已发起';
    }
    if (value.endsWith('_started') || value.endsWith('_start')) {
      return '流程开始执行';
    }
    if (value.endsWith('_completed') || value.endsWith('_finished')) {
      return '流程执行完成';
    }
    if (value.endsWith('_failed') || value.endsWith('_failure')) {
      return '流程执行失败';
    }
    if (value.endsWith('_received')) {
      return '流程已收到数据';
    }
    if (value.endsWith('_cancelled')) {
      return '流程已取消';
    }
    return '流程事件';
  }

  String? _chineseEventTokenLabel(String value) {
    return switch (value) {
      'ack' => '确认',
      'admission' => '准入',
      'admitted' => '准入通过',
      'aggregate' => '汇总',
      'app' => '应用',
      'armed' => '计时开始',
      'attempt' => '尝试',
      'authentication' => '认证',
      'battery' => '电量',
      'bind' => '绑定',
      'bluetooth' => '蓝牙',
      'cancelled' => '已取消',
      'candidate' => '候选设备',
      'ccc' => 'CCC',
      'checked' => '已校验',
      'client' => '客户端',
      'close' => '关闭',
      'closed' => '已关闭',
      'closing' => '正在关闭',
      'command' => '命令',
      'completed' => '完成',
      'configuration' => '配置',
      'connect' => '连接',
      'connected' => '已连接',
      'connection' => '连接',
      'contract' => '协议契约',
      'count' => '数量',
      'decode' => '解码',
      'decoded' => '已解码',
      'device' => '设备',
      'discovery' => '服务发现',
      'download' => '下载',
      'error' => '异常',
      'event' => '事件',
      'evt' => 'EVT',
      'exhausted' => '已耗尽',
      'failed' => '失败',
      'failure' => '失败',
      'file' => '文件',
      'finished' => '结束',
      'forwarded' => '已转发',
      'frame' => '帧',
      'gatt' => 'GATT',
      'history' => '历史',
      'ignored' => '已忽略',
      'import' => '导入',
      'interrupted' => '已中断',
      'legacy' => 'V1认证',
      'lifecycle' => '生命周期',
      'list' => '列表',
      'load' => '读取',
      'loaded' => '已读取',
      'manual' => '手动',
      'matched' => '已匹配',
      'mismatch' => '不匹配',
      'mtu' => 'MTU',
      'native' => '原生',
      'notification' => '通知',
      'open' => '打开',
      'opened' => '已打开',
      'pause' => '暂停',
      'paused' => '已暂停',
      'permission' => '权限',
      'profile' => '特征配置',
      'protocol' => '协议',
      'queued' => '已排队',
      'read' => '读取',
      'ready' => '就绪',
      'received' => '已收到',
      'reconnect' => '回连',
      'record' => '录音',
      'rejected' => '已拒绝',
      'remove' => '移除',
      'removed' => '已移除',
      'requested' => '请求',
      'response' => '回包',
      'restore' => '恢复',
      'restored' => '已恢复',
      'result' => '结果',
      'retry' => '重试',
      'scan' => '扫描',
      'security' => '安全码',
      'service' => '服务',
      'session' => '会话',
      'started' => '开始',
      'state' => '状态',
      'status' => '状态',
      'stop' => '停止',
      'stopped' => '已停止',
      'storage' => '存储',
      'stream' => '流式',
      'subscription' => '订阅',
      'subscribed' => '已订阅',
      'suppressed' => '已抑制',
      'synchronization' => '同步',
      'timeout' => '超时',
      'transfer' => '传输',
      'transmit' => '发送',
      'transport' => '传输通道',
      'ui' => '界面',
      'unmatched' => '未匹配',
      'unexpected' => '异常',
      'update' => '更新',
      'changed' => '变更',
      'updated' => '已更新',
      'validation' => '校验',
      'verified' => '已验证',
      'wait' => '等待',
      'waiting' => '等待',
      'window' => '窗口',
      'write' => '写入',
      'dvt' => 'DVT',
      'wqota' => '固件升级',
      'tx' => '发送',
      'rx' => '接收',
      'raw' => '原始字节',
      'durable' => '可靠保存',
      'probe' => '验证',
      'written' => '已写入',
      _ => null,
    };
  }

  Object? _formatValue(Object? value) {
    if (value is Map || value is Iterable) {
      return jsonEncode(value);
    }
    return value;
  }
}
