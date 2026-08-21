// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $EvidenceBundlesTable extends EvidenceBundles
    with TableInfo<$EvidenceBundlesTable, EvidenceBundleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EvidenceBundlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firmwareVersionMeta = const VerificationMeta(
    'firmwareVersion',
  );
  @override
  late final GeneratedColumn<String> firmwareVersion = GeneratedColumn<String>(
    'firmware_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verdictMeta = const VerificationMeta(
    'verdict',
  );
  @override
  late final GeneratedColumn<String> verdict = GeneratedColumn<String>(
    'verdict',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manualNoteMeta = const VerificationMeta(
    'manualNote',
  );
  @override
  late final GeneratedColumn<String> manualNote = GeneratedColumn<String>(
    'manual_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _diagnosticJsonMeta = const VerificationMeta(
    'diagnosticJson',
  );
  @override
  late final GeneratedColumn<String> diagnosticJson = GeneratedColumn<String>(
    'diagnostic_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    deviceId,
    deviceName,
    firmwareVersion,
    verdict,
    reason,
    manualNote,
    diagnosticJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'evidence_bundles';
  @override
  VerificationContext validateIntegrity(
    Insertable<EvidenceBundleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceNameMeta);
    }
    if (data.containsKey('firmware_version')) {
      context.handle(
        _firmwareVersionMeta,
        firmwareVersion.isAcceptableOrUnknown(
          data['firmware_version']!,
          _firmwareVersionMeta,
        ),
      );
    }
    if (data.containsKey('verdict')) {
      context.handle(
        _verdictMeta,
        verdict.isAcceptableOrUnknown(data['verdict']!, _verdictMeta),
      );
    } else if (isInserting) {
      context.missing(_verdictMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('manual_note')) {
      context.handle(
        _manualNoteMeta,
        manualNote.isAcceptableOrUnknown(data['manual_note']!, _manualNoteMeta),
      );
    }
    if (data.containsKey('diagnostic_json')) {
      context.handle(
        _diagnosticJsonMeta,
        diagnosticJson.isAcceptableOrUnknown(
          data['diagnostic_json']!,
          _diagnosticJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_diagnosticJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EvidenceBundleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EvidenceBundleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      )!,
      firmwareVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}firmware_version'],
      ),
      verdict: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verdict'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      manualNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manual_note'],
      ),
      diagnosticJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}diagnostic_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $EvidenceBundlesTable createAlias(String alias) {
    return $EvidenceBundlesTable(attachedDatabase, alias);
  }
}

class EvidenceBundleRow extends DataClass
    implements Insertable<EvidenceBundleRow> {
  final String id;
  final String sessionId;
  final String deviceId;
  final String deviceName;
  final String? firmwareVersion;
  final String verdict;
  final String reason;
  final String? manualNote;
  final String diagnosticJson;
  final DateTime createdAt;
  const EvidenceBundleRow({
    required this.id,
    required this.sessionId,
    required this.deviceId,
    required this.deviceName,
    this.firmwareVersion,
    required this.verdict,
    required this.reason,
    this.manualNote,
    required this.diagnosticJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['device_id'] = Variable<String>(deviceId);
    map['device_name'] = Variable<String>(deviceName);
    if (!nullToAbsent || firmwareVersion != null) {
      map['firmware_version'] = Variable<String>(firmwareVersion);
    }
    map['verdict'] = Variable<String>(verdict);
    map['reason'] = Variable<String>(reason);
    if (!nullToAbsent || manualNote != null) {
      map['manual_note'] = Variable<String>(manualNote);
    }
    map['diagnostic_json'] = Variable<String>(diagnosticJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  EvidenceBundlesCompanion toCompanion(bool nullToAbsent) {
    return EvidenceBundlesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      deviceId: Value(deviceId),
      deviceName: Value(deviceName),
      firmwareVersion: firmwareVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(firmwareVersion),
      verdict: Value(verdict),
      reason: Value(reason),
      manualNote: manualNote == null && nullToAbsent
          ? const Value.absent()
          : Value(manualNote),
      diagnosticJson: Value(diagnosticJson),
      createdAt: Value(createdAt),
    );
  }

  factory EvidenceBundleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EvidenceBundleRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      firmwareVersion: serializer.fromJson<String?>(json['firmwareVersion']),
      verdict: serializer.fromJson<String>(json['verdict']),
      reason: serializer.fromJson<String>(json['reason']),
      manualNote: serializer.fromJson<String?>(json['manualNote']),
      diagnosticJson: serializer.fromJson<String>(json['diagnosticJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'deviceId': serializer.toJson<String>(deviceId),
      'deviceName': serializer.toJson<String>(deviceName),
      'firmwareVersion': serializer.toJson<String?>(firmwareVersion),
      'verdict': serializer.toJson<String>(verdict),
      'reason': serializer.toJson<String>(reason),
      'manualNote': serializer.toJson<String?>(manualNote),
      'diagnosticJson': serializer.toJson<String>(diagnosticJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  EvidenceBundleRow copyWith({
    String? id,
    String? sessionId,
    String? deviceId,
    String? deviceName,
    Value<String?> firmwareVersion = const Value.absent(),
    String? verdict,
    String? reason,
    Value<String?> manualNote = const Value.absent(),
    String? diagnosticJson,
    DateTime? createdAt,
  }) => EvidenceBundleRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    firmwareVersion: firmwareVersion.present
        ? firmwareVersion.value
        : this.firmwareVersion,
    verdict: verdict ?? this.verdict,
    reason: reason ?? this.reason,
    manualNote: manualNote.present ? manualNote.value : this.manualNote,
    diagnosticJson: diagnosticJson ?? this.diagnosticJson,
    createdAt: createdAt ?? this.createdAt,
  );
  EvidenceBundleRow copyWithCompanion(EvidenceBundlesCompanion data) {
    return EvidenceBundleRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
      firmwareVersion: data.firmwareVersion.present
          ? data.firmwareVersion.value
          : this.firmwareVersion,
      verdict: data.verdict.present ? data.verdict.value : this.verdict,
      reason: data.reason.present ? data.reason.value : this.reason,
      manualNote: data.manualNote.present
          ? data.manualNote.value
          : this.manualNote,
      diagnosticJson: data.diagnosticJson.present
          ? data.diagnosticJson.value
          : this.diagnosticJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EvidenceBundleRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('firmwareVersion: $firmwareVersion, ')
          ..write('verdict: $verdict, ')
          ..write('reason: $reason, ')
          ..write('manualNote: $manualNote, ')
          ..write('diagnosticJson: $diagnosticJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    deviceId,
    deviceName,
    firmwareVersion,
    verdict,
    reason,
    manualNote,
    diagnosticJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EvidenceBundleRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.deviceId == this.deviceId &&
          other.deviceName == this.deviceName &&
          other.firmwareVersion == this.firmwareVersion &&
          other.verdict == this.verdict &&
          other.reason == this.reason &&
          other.manualNote == this.manualNote &&
          other.diagnosticJson == this.diagnosticJson &&
          other.createdAt == this.createdAt);
}

class EvidenceBundlesCompanion extends UpdateCompanion<EvidenceBundleRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> deviceId;
  final Value<String> deviceName;
  final Value<String?> firmwareVersion;
  final Value<String> verdict;
  final Value<String> reason;
  final Value<String?> manualNote;
  final Value<String> diagnosticJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const EvidenceBundlesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.firmwareVersion = const Value.absent(),
    this.verdict = const Value.absent(),
    this.reason = const Value.absent(),
    this.manualNote = const Value.absent(),
    this.diagnosticJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EvidenceBundlesCompanion.insert({
    required String id,
    required String sessionId,
    required String deviceId,
    required String deviceName,
    this.firmwareVersion = const Value.absent(),
    required String verdict,
    required String reason,
    this.manualNote = const Value.absent(),
    required String diagnosticJson,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       deviceId = Value(deviceId),
       deviceName = Value(deviceName),
       verdict = Value(verdict),
       reason = Value(reason),
       diagnosticJson = Value(diagnosticJson),
       createdAt = Value(createdAt);
  static Insertable<EvidenceBundleRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? deviceId,
    Expression<String>? deviceName,
    Expression<String>? firmwareVersion,
    Expression<String>? verdict,
    Expression<String>? reason,
    Expression<String>? manualNote,
    Expression<String>? diagnosticJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
      if (firmwareVersion != null) 'firmware_version': firmwareVersion,
      if (verdict != null) 'verdict': verdict,
      if (reason != null) 'reason': reason,
      if (manualNote != null) 'manual_note': manualNote,
      if (diagnosticJson != null) 'diagnostic_json': diagnosticJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EvidenceBundlesCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? deviceId,
    Value<String>? deviceName,
    Value<String?>? firmwareVersion,
    Value<String>? verdict,
    Value<String>? reason,
    Value<String?>? manualNote,
    Value<String>? diagnosticJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return EvidenceBundlesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      verdict: verdict ?? this.verdict,
      reason: reason ?? this.reason,
      manualNote: manualNote ?? this.manualNote,
      diagnosticJson: diagnosticJson ?? this.diagnosticJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (firmwareVersion.present) {
      map['firmware_version'] = Variable<String>(firmwareVersion.value);
    }
    if (verdict.present) {
      map['verdict'] = Variable<String>(verdict.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (manualNote.present) {
      map['manual_note'] = Variable<String>(manualNote.value);
    }
    if (diagnosticJson.present) {
      map['diagnostic_json'] = Variable<String>(diagnosticJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EvidenceBundlesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('firmwareVersion: $firmwareVersion, ')
          ..write('verdict: $verdict, ')
          ..write('reason: $reason, ')
          ..write('manualNote: $manualNote, ')
          ..write('diagnosticJson: $diagnosticJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionEventsTable extends SessionEvents
    with TableInfo<$SessionEventsTable, EvidenceRecordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bundleIdMeta = const VerificationMeta(
    'bundleId',
  );
  @override
  late final GeneratedColumn<String> bundleId = GeneratedColumn<String>(
    'bundle_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordKindMeta = const VerificationMeta(
    'recordKind',
  );
  @override
  late final GeneratedColumn<String> recordKind = GeneratedColumn<String>(
    'record_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bundleId,
    sequence,
    recordKind,
    source,
    occurredAt,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<EvidenceRecordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('bundle_id')) {
      context.handle(
        _bundleIdMeta,
        bundleId.isAcceptableOrUnknown(data['bundle_id']!, _bundleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bundleIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('record_kind')) {
      context.handle(
        _recordKindMeta,
        recordKind.isAcceptableOrUnknown(data['record_kind']!, _recordKindMeta),
      );
    } else if (isInserting) {
      context.missing(_recordKindMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EvidenceRecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EvidenceRecordRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bundleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bundle_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      recordKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_kind'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $SessionEventsTable createAlias(String alias) {
    return $SessionEventsTable(attachedDatabase, alias);
  }
}

class EvidenceRecordRow extends DataClass
    implements Insertable<EvidenceRecordRow> {
  final int id;
  final String bundleId;
  final int sequence;
  final String recordKind;
  final String source;
  final DateTime occurredAt;
  final String payloadJson;
  const EvidenceRecordRow({
    required this.id,
    required this.bundleId,
    required this.sequence,
    required this.recordKind,
    required this.source,
    required this.occurredAt,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['bundle_id'] = Variable<String>(bundleId);
    map['sequence'] = Variable<int>(sequence);
    map['record_kind'] = Variable<String>(recordKind);
    map['source'] = Variable<String>(source);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  SessionEventsCompanion toCompanion(bool nullToAbsent) {
    return SessionEventsCompanion(
      id: Value(id),
      bundleId: Value(bundleId),
      sequence: Value(sequence),
      recordKind: Value(recordKind),
      source: Value(source),
      occurredAt: Value(occurredAt),
      payloadJson: Value(payloadJson),
    );
  }

  factory EvidenceRecordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EvidenceRecordRow(
      id: serializer.fromJson<int>(json['id']),
      bundleId: serializer.fromJson<String>(json['bundleId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      recordKind: serializer.fromJson<String>(json['recordKind']),
      source: serializer.fromJson<String>(json['source']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bundleId': serializer.toJson<String>(bundleId),
      'sequence': serializer.toJson<int>(sequence),
      'recordKind': serializer.toJson<String>(recordKind),
      'source': serializer.toJson<String>(source),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  EvidenceRecordRow copyWith({
    int? id,
    String? bundleId,
    int? sequence,
    String? recordKind,
    String? source,
    DateTime? occurredAt,
    String? payloadJson,
  }) => EvidenceRecordRow(
    id: id ?? this.id,
    bundleId: bundleId ?? this.bundleId,
    sequence: sequence ?? this.sequence,
    recordKind: recordKind ?? this.recordKind,
    source: source ?? this.source,
    occurredAt: occurredAt ?? this.occurredAt,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  EvidenceRecordRow copyWithCompanion(SessionEventsCompanion data) {
    return EvidenceRecordRow(
      id: data.id.present ? data.id.value : this.id,
      bundleId: data.bundleId.present ? data.bundleId.value : this.bundleId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      recordKind: data.recordKind.present
          ? data.recordKind.value
          : this.recordKind,
      source: data.source.present ? data.source.value : this.source,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EvidenceRecordRow(')
          ..write('id: $id, ')
          ..write('bundleId: $bundleId, ')
          ..write('sequence: $sequence, ')
          ..write('recordKind: $recordKind, ')
          ..write('source: $source, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bundleId,
    sequence,
    recordKind,
    source,
    occurredAt,
    payloadJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EvidenceRecordRow &&
          other.id == this.id &&
          other.bundleId == this.bundleId &&
          other.sequence == this.sequence &&
          other.recordKind == this.recordKind &&
          other.source == this.source &&
          other.occurredAt == this.occurredAt &&
          other.payloadJson == this.payloadJson);
}

class SessionEventsCompanion extends UpdateCompanion<EvidenceRecordRow> {
  final Value<int> id;
  final Value<String> bundleId;
  final Value<int> sequence;
  final Value<String> recordKind;
  final Value<String> source;
  final Value<DateTime> occurredAt;
  final Value<String> payloadJson;
  const SessionEventsCompanion({
    this.id = const Value.absent(),
    this.bundleId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.recordKind = const Value.absent(),
    this.source = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
  });
  SessionEventsCompanion.insert({
    this.id = const Value.absent(),
    required String bundleId,
    required int sequence,
    required String recordKind,
    required String source,
    required DateTime occurredAt,
    required String payloadJson,
  }) : bundleId = Value(bundleId),
       sequence = Value(sequence),
       recordKind = Value(recordKind),
       source = Value(source),
       occurredAt = Value(occurredAt),
       payloadJson = Value(payloadJson);
  static Insertable<EvidenceRecordRow> custom({
    Expression<int>? id,
    Expression<String>? bundleId,
    Expression<int>? sequence,
    Expression<String>? recordKind,
    Expression<String>? source,
    Expression<DateTime>? occurredAt,
    Expression<String>? payloadJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bundleId != null) 'bundle_id': bundleId,
      if (sequence != null) 'sequence': sequence,
      if (recordKind != null) 'record_kind': recordKind,
      if (source != null) 'source': source,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (payloadJson != null) 'payload_json': payloadJson,
    });
  }

  SessionEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? bundleId,
    Value<int>? sequence,
    Value<String>? recordKind,
    Value<String>? source,
    Value<DateTime>? occurredAt,
    Value<String>? payloadJson,
  }) {
    return SessionEventsCompanion(
      id: id ?? this.id,
      bundleId: bundleId ?? this.bundleId,
      sequence: sequence ?? this.sequence,
      recordKind: recordKind ?? this.recordKind,
      source: source ?? this.source,
      occurredAt: occurredAt ?? this.occurredAt,
      payloadJson: payloadJson ?? this.payloadJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bundleId.present) {
      map['bundle_id'] = Variable<String>(bundleId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (recordKind.present) {
      map['record_kind'] = Variable<String>(recordKind.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionEventsCompanion(')
          ..write('id: $id, ')
          ..write('bundleId: $bundleId, ')
          ..write('sequence: $sequence, ')
          ..write('recordKind: $recordKind, ')
          ..write('source: $source, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $EvidenceBundlesTable evidenceBundles = $EvidenceBundlesTable(
    this,
  );
  late final $SessionEventsTable sessionEvents = $SessionEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    evidenceBundles,
    sessionEvents,
  ];
}

typedef $$EvidenceBundlesTableCreateCompanionBuilder =
    EvidenceBundlesCompanion Function({
      required String id,
      required String sessionId,
      required String deviceId,
      required String deviceName,
      Value<String?> firmwareVersion,
      required String verdict,
      required String reason,
      Value<String?> manualNote,
      required String diagnosticJson,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$EvidenceBundlesTableUpdateCompanionBuilder =
    EvidenceBundlesCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> deviceId,
      Value<String> deviceName,
      Value<String?> firmwareVersion,
      Value<String> verdict,
      Value<String> reason,
      Value<String?> manualNote,
      Value<String> diagnosticJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$EvidenceBundlesTableFilterComposer
    extends Composer<_$AppDatabase, $EvidenceBundlesTable> {
  $$EvidenceBundlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firmwareVersion => $composableBuilder(
    column: $table.firmwareVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verdict => $composableBuilder(
    column: $table.verdict,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manualNote => $composableBuilder(
    column: $table.manualNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get diagnosticJson => $composableBuilder(
    column: $table.diagnosticJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EvidenceBundlesTableOrderingComposer
    extends Composer<_$AppDatabase, $EvidenceBundlesTable> {
  $$EvidenceBundlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firmwareVersion => $composableBuilder(
    column: $table.firmwareVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verdict => $composableBuilder(
    column: $table.verdict,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manualNote => $composableBuilder(
    column: $table.manualNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get diagnosticJson => $composableBuilder(
    column: $table.diagnosticJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EvidenceBundlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EvidenceBundlesTable> {
  $$EvidenceBundlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firmwareVersion => $composableBuilder(
    column: $table.firmwareVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verdict =>
      $composableBuilder(column: $table.verdict, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get manualNote => $composableBuilder(
    column: $table.manualNote,
    builder: (column) => column,
  );

  GeneratedColumn<String> get diagnosticJson => $composableBuilder(
    column: $table.diagnosticJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$EvidenceBundlesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EvidenceBundlesTable,
          EvidenceBundleRow,
          $$EvidenceBundlesTableFilterComposer,
          $$EvidenceBundlesTableOrderingComposer,
          $$EvidenceBundlesTableAnnotationComposer,
          $$EvidenceBundlesTableCreateCompanionBuilder,
          $$EvidenceBundlesTableUpdateCompanionBuilder,
          (
            EvidenceBundleRow,
            BaseReferences<
              _$AppDatabase,
              $EvidenceBundlesTable,
              EvidenceBundleRow
            >,
          ),
          EvidenceBundleRow,
          PrefetchHooks Function()
        > {
  $$EvidenceBundlesTableTableManager(
    _$AppDatabase db,
    $EvidenceBundlesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EvidenceBundlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EvidenceBundlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EvidenceBundlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> deviceName = const Value.absent(),
                Value<String?> firmwareVersion = const Value.absent(),
                Value<String> verdict = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<String?> manualNote = const Value.absent(),
                Value<String> diagnosticJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EvidenceBundlesCompanion(
                id: id,
                sessionId: sessionId,
                deviceId: deviceId,
                deviceName: deviceName,
                firmwareVersion: firmwareVersion,
                verdict: verdict,
                reason: reason,
                manualNote: manualNote,
                diagnosticJson: diagnosticJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String deviceId,
                required String deviceName,
                Value<String?> firmwareVersion = const Value.absent(),
                required String verdict,
                required String reason,
                Value<String?> manualNote = const Value.absent(),
                required String diagnosticJson,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => EvidenceBundlesCompanion.insert(
                id: id,
                sessionId: sessionId,
                deviceId: deviceId,
                deviceName: deviceName,
                firmwareVersion: firmwareVersion,
                verdict: verdict,
                reason: reason,
                manualNote: manualNote,
                diagnosticJson: diagnosticJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EvidenceBundlesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EvidenceBundlesTable,
      EvidenceBundleRow,
      $$EvidenceBundlesTableFilterComposer,
      $$EvidenceBundlesTableOrderingComposer,
      $$EvidenceBundlesTableAnnotationComposer,
      $$EvidenceBundlesTableCreateCompanionBuilder,
      $$EvidenceBundlesTableUpdateCompanionBuilder,
      (
        EvidenceBundleRow,
        BaseReferences<_$AppDatabase, $EvidenceBundlesTable, EvidenceBundleRow>,
      ),
      EvidenceBundleRow,
      PrefetchHooks Function()
    >;
typedef $$SessionEventsTableCreateCompanionBuilder =
    SessionEventsCompanion Function({
      Value<int> id,
      required String bundleId,
      required int sequence,
      required String recordKind,
      required String source,
      required DateTime occurredAt,
      required String payloadJson,
    });
typedef $$SessionEventsTableUpdateCompanionBuilder =
    SessionEventsCompanion Function({
      Value<int> id,
      Value<String> bundleId,
      Value<int> sequence,
      Value<String> recordKind,
      Value<String> source,
      Value<DateTime> occurredAt,
      Value<String> payloadJson,
    });

class $$SessionEventsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionEventsTable> {
  $$SessionEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bundleId => $composableBuilder(
    column: $table.bundleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordKind => $composableBuilder(
    column: $table.recordKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionEventsTable> {
  $$SessionEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bundleId => $composableBuilder(
    column: $table.bundleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordKind => $composableBuilder(
    column: $table.recordKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionEventsTable> {
  $$SessionEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bundleId =>
      $composableBuilder(column: $table.bundleId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get recordKind => $composableBuilder(
    column: $table.recordKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$SessionEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionEventsTable,
          EvidenceRecordRow,
          $$SessionEventsTableFilterComposer,
          $$SessionEventsTableOrderingComposer,
          $$SessionEventsTableAnnotationComposer,
          $$SessionEventsTableCreateCompanionBuilder,
          $$SessionEventsTableUpdateCompanionBuilder,
          (
            EvidenceRecordRow,
            BaseReferences<
              _$AppDatabase,
              $SessionEventsTable,
              EvidenceRecordRow
            >,
          ),
          EvidenceRecordRow,
          PrefetchHooks Function()
        > {
  $$SessionEventsTableTableManager(_$AppDatabase db, $SessionEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bundleId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> recordKind = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
              }) => SessionEventsCompanion(
                id: id,
                bundleId: bundleId,
                sequence: sequence,
                recordKind: recordKind,
                source: source,
                occurredAt: occurredAt,
                payloadJson: payloadJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bundleId,
                required int sequence,
                required String recordKind,
                required String source,
                required DateTime occurredAt,
                required String payloadJson,
              }) => SessionEventsCompanion.insert(
                id: id,
                bundleId: bundleId,
                sequence: sequence,
                recordKind: recordKind,
                source: source,
                occurredAt: occurredAt,
                payloadJson: payloadJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionEventsTable,
      EvidenceRecordRow,
      $$SessionEventsTableFilterComposer,
      $$SessionEventsTableOrderingComposer,
      $$SessionEventsTableAnnotationComposer,
      $$SessionEventsTableCreateCompanionBuilder,
      $$SessionEventsTableUpdateCompanionBuilder,
      (
        EvidenceRecordRow,
        BaseReferences<_$AppDatabase, $SessionEventsTable, EvidenceRecordRow>,
      ),
      EvidenceRecordRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$EvidenceBundlesTableTableManager get evidenceBundles =>
      $$EvidenceBundlesTableTableManager(_db, _db.evidenceBundles);
  $$SessionEventsTableTableManager get sessionEvents =>
      $$SessionEventsTableTableManager(_db, _db.sessionEvents);
}
