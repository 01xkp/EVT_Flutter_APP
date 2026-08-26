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

class $LocalRecordingsTable extends LocalRecordings
    with TableInfo<$LocalRecordingsTable, LocalRecordingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRecordingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
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
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    relativePath,
    createdAt,
    completedAt,
    durationMs,
    sizeBytes,
    state,
    failureReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_recordings';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalRecordingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalRecordingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRecordingRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
    );
  }

  @override
  $LocalRecordingsTable createAlias(String alias) {
    return $LocalRecordingsTable(attachedDatabase, alias);
  }
}

class LocalRecordingRow extends DataClass
    implements Insertable<LocalRecordingRow> {
  final String id;
  final String title;
  final String relativePath;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int? durationMs;
  final int? sizeBytes;
  final String state;
  final String? failureReason;
  const LocalRecordingRow({
    required this.id,
    required this.title,
    required this.relativePath,
    required this.createdAt,
    this.completedAt,
    this.durationMs,
    this.sizeBytes,
    required this.state,
    this.failureReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['relative_path'] = Variable<String>(relativePath);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || sizeBytes != null) {
      map['size_bytes'] = Variable<int>(sizeBytes);
    }
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    return map;
  }

  LocalRecordingsCompanion toCompanion(bool nullToAbsent) {
    return LocalRecordingsCompanion(
      id: Value(id),
      title: Value(title),
      relativePath: Value(relativePath),
      createdAt: Value(createdAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      sizeBytes: sizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeBytes),
      state: Value(state),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
    );
  }

  factory LocalRecordingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRecordingRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      sizeBytes: serializer.fromJson<int?>(json['sizeBytes']),
      state: serializer.fromJson<String>(json['state']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'relativePath': serializer.toJson<String>(relativePath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'durationMs': serializer.toJson<int?>(durationMs),
      'sizeBytes': serializer.toJson<int?>(sizeBytes),
      'state': serializer.toJson<String>(state),
      'failureReason': serializer.toJson<String?>(failureReason),
    };
  }

  LocalRecordingRow copyWith({
    String? id,
    String? title,
    String? relativePath,
    DateTime? createdAt,
    Value<DateTime?> completedAt = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<int?> sizeBytes = const Value.absent(),
    String? state,
    Value<String?> failureReason = const Value.absent(),
  }) => LocalRecordingRow(
    id: id ?? this.id,
    title: title ?? this.title,
    relativePath: relativePath ?? this.relativePath,
    createdAt: createdAt ?? this.createdAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    state: state ?? this.state,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
  );
  LocalRecordingRow copyWithCompanion(LocalRecordingsCompanion data) {
    return LocalRecordingRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      state: data.state.present ? data.state.value : this.state,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRecordingRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('relativePath: $relativePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('state: $state, ')
          ..write('failureReason: $failureReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    relativePath,
    createdAt,
    completedAt,
    durationMs,
    sizeBytes,
    state,
    failureReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRecordingRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.relativePath == this.relativePath &&
          other.createdAt == this.createdAt &&
          other.completedAt == this.completedAt &&
          other.durationMs == this.durationMs &&
          other.sizeBytes == this.sizeBytes &&
          other.state == this.state &&
          other.failureReason == this.failureReason);
}

class LocalRecordingsCompanion extends UpdateCompanion<LocalRecordingRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> relativePath;
  final Value<DateTime> createdAt;
  final Value<DateTime?> completedAt;
  final Value<int?> durationMs;
  final Value<int?> sizeBytes;
  final Value<String> state;
  final Value<String?> failureReason;
  final Value<int> rowid;
  const LocalRecordingsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.state = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalRecordingsCompanion.insert({
    required String id,
    required String title,
    required String relativePath,
    required DateTime createdAt,
    this.completedAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    required String state,
    this.failureReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       relativePath = Value(relativePath),
       createdAt = Value(createdAt),
       state = Value(state);
  static Insertable<LocalRecordingRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? relativePath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? completedAt,
    Expression<int>? durationMs,
    Expression<int>? sizeBytes,
    Expression<String>? state,
    Expression<String>? failureReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (relativePath != null) 'relative_path': relativePath,
      if (createdAt != null) 'created_at': createdAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (durationMs != null) 'duration_ms': durationMs,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (state != null) 'state': state,
      if (failureReason != null) 'failure_reason': failureReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalRecordingsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? relativePath,
    Value<DateTime>? createdAt,
    Value<DateTime?>? completedAt,
    Value<int?>? durationMs,
    Value<int?>? sizeBytes,
    Value<String>? state,
    Value<String?>? failureReason,
    Value<int>? rowid,
  }) {
    return LocalRecordingsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      relativePath: relativePath ?? this.relativePath,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      durationMs: durationMs ?? this.durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      state: state ?? this.state,
      failureReason: failureReason ?? this.failureReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRecordingsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('relativePath: $relativePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('state: $state, ')
          ..write('failureReason: $failureReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ResearchCapturesTable extends ResearchCaptures
    with TableInfo<$ResearchCapturesTable, ResearchCaptureRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResearchCapturesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _participantIdMeta = const VerificationMeta(
    'participantId',
  );
  @override
  late final GeneratedColumn<String> participantId = GeneratedColumn<String>(
    'participant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalLocalRecordingIdMeta =
      const VerificationMeta('originalLocalRecordingId');
  @override
  late final GeneratedColumn<String> originalLocalRecordingId =
      GeneratedColumn<String>(
        'original_local_recording_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
      );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processingStateMeta = const VerificationMeta(
    'processingState',
  );
  @override
  late final GeneratedColumn<String> processingState = GeneratedColumn<String>(
    'processing_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inboxStateMeta = const VerificationMeta(
    'inboxState',
  );
  @override
  late final GeneratedColumn<String> inboxState = GeneratedColumn<String>(
    'inbox_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _asrSegmentsJsonMeta = const VerificationMeta(
    'asrSegmentsJson',
  );
  @override
  late final GeneratedColumn<String> asrSegmentsJson = GeneratedColumn<String>(
    'asr_segments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _generationTaskIdMeta = const VerificationMeta(
    'generationTaskId',
  );
  @override
  late final GeneratedColumn<String> generationTaskId = GeneratedColumn<String>(
    'generation_task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawTranscriptMeta = const VerificationMeta(
    'rawTranscript',
  );
  @override
  late final GeneratedColumn<String> rawTranscript = GeneratedColumn<String>(
    'raw_transcript',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _correctedTranscriptMeta =
      const VerificationMeta('correctedTranscript');
  @override
  late final GeneratedColumn<String> correctedTranscript =
      GeneratedColumn<String>(
        'corrected_transcript',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _actionContextMeta = const VerificationMeta(
    'actionContext',
  );
  @override
  late final GeneratedColumn<String> actionContext = GeneratedColumn<String>(
    'action_context',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  @override
  late final GeneratedColumn<DateTime> openedAt = GeneratedColumn<DateTime>(
    'opened_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _handledAtMeta = const VerificationMeta(
    'handledAt',
  );
  @override
  late final GeneratedColumn<DateTime> handledAt = GeneratedColumn<DateTime>(
    'handled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    participantId,
    origin,
    sourceType,
    originalLocalRecordingId,
    relativePath,
    durationMs,
    createdAt,
    completedAt,
    processingState,
    inboxState,
    jobId,
    asrSegmentsJson,
    noteId,
    generationTaskId,
    rawTranscript,
    correctedTranscript,
    title,
    summary,
    tagsJson,
    actionContext,
    failureReason,
    openedAt,
    handledAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'research_captures';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResearchCaptureRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('participant_id')) {
      context.handle(
        _participantIdMeta,
        participantId.isAcceptableOrUnknown(
          data['participant_id']!,
          _participantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_participantIdMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTypeMeta);
    }
    if (data.containsKey('original_local_recording_id')) {
      context.handle(
        _originalLocalRecordingIdMeta,
        originalLocalRecordingId.isAcceptableOrUnknown(
          data['original_local_recording_id']!,
          _originalLocalRecordingIdMeta,
        ),
      );
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('processing_state')) {
      context.handle(
        _processingStateMeta,
        processingState.isAcceptableOrUnknown(
          data['processing_state']!,
          _processingStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_processingStateMeta);
    }
    if (data.containsKey('inbox_state')) {
      context.handle(
        _inboxStateMeta,
        inboxState.isAcceptableOrUnknown(data['inbox_state']!, _inboxStateMeta),
      );
    } else if (isInserting) {
      context.missing(_inboxStateMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    }
    if (data.containsKey('asr_segments_json')) {
      context.handle(
        _asrSegmentsJsonMeta,
        asrSegmentsJson.isAcceptableOrUnknown(
          data['asr_segments_json']!,
          _asrSegmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    }
    if (data.containsKey('generation_task_id')) {
      context.handle(
        _generationTaskIdMeta,
        generationTaskId.isAcceptableOrUnknown(
          data['generation_task_id']!,
          _generationTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('raw_transcript')) {
      context.handle(
        _rawTranscriptMeta,
        rawTranscript.isAcceptableOrUnknown(
          data['raw_transcript']!,
          _rawTranscriptMeta,
        ),
      );
    }
    if (data.containsKey('corrected_transcript')) {
      context.handle(
        _correctedTranscriptMeta,
        correctedTranscript.isAcceptableOrUnknown(
          data['corrected_transcript']!,
          _correctedTranscriptMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('action_context')) {
      context.handle(
        _actionContextMeta,
        actionContext.isAcceptableOrUnknown(
          data['action_context']!,
          _actionContextMeta,
        ),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    if (data.containsKey('opened_at')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['opened_at']!, _openedAtMeta),
      );
    }
    if (data.containsKey('handled_at')) {
      context.handle(
        _handledAtMeta,
        handledAt.isAcceptableOrUnknown(data['handled_at']!, _handledAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ResearchCaptureRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResearchCaptureRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      participantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participant_id'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      )!,
      originalLocalRecordingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_local_recording_id'],
      ),
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      processingState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_state'],
      )!,
      inboxState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inbox_state'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      ),
      asrSegmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asr_segments_json'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      ),
      generationTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}generation_task_id'],
      ),
      rawTranscript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_transcript'],
      ),
      correctedTranscript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}corrected_transcript'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      actionContext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_context'],
      ),
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_at'],
      ),
      handledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}handled_at'],
      ),
    );
  }

  @override
  $ResearchCapturesTable createAlias(String alias) {
    return $ResearchCapturesTable(attachedDatabase, alias);
  }
}

class ResearchCaptureRow extends DataClass
    implements Insertable<ResearchCaptureRow> {
  final String id;
  final String participantId;
  final String origin;
  final String sourceType;
  final String? originalLocalRecordingId;
  final String relativePath;
  final int durationMs;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String processingState;
  final String inboxState;
  final String? jobId;
  final String asrSegmentsJson;
  final String? noteId;
  final String? generationTaskId;
  final String? rawTranscript;
  final String? correctedTranscript;
  final String? title;
  final String? summary;
  final String tagsJson;
  final String? actionContext;
  final String? failureReason;
  final DateTime? openedAt;
  final DateTime? handledAt;
  const ResearchCaptureRow({
    required this.id,
    required this.participantId,
    required this.origin,
    required this.sourceType,
    this.originalLocalRecordingId,
    required this.relativePath,
    required this.durationMs,
    required this.createdAt,
    this.completedAt,
    required this.processingState,
    required this.inboxState,
    this.jobId,
    required this.asrSegmentsJson,
    this.noteId,
    this.generationTaskId,
    this.rawTranscript,
    this.correctedTranscript,
    this.title,
    this.summary,
    required this.tagsJson,
    this.actionContext,
    this.failureReason,
    this.openedAt,
    this.handledAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['participant_id'] = Variable<String>(participantId);
    map['origin'] = Variable<String>(origin);
    map['source_type'] = Variable<String>(sourceType);
    if (!nullToAbsent || originalLocalRecordingId != null) {
      map['original_local_recording_id'] = Variable<String>(
        originalLocalRecordingId,
      );
    }
    map['relative_path'] = Variable<String>(relativePath);
    map['duration_ms'] = Variable<int>(durationMs);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['processing_state'] = Variable<String>(processingState);
    map['inbox_state'] = Variable<String>(inboxState);
    if (!nullToAbsent || jobId != null) {
      map['job_id'] = Variable<String>(jobId);
    }
    map['asr_segments_json'] = Variable<String>(asrSegmentsJson);
    if (!nullToAbsent || noteId != null) {
      map['note_id'] = Variable<String>(noteId);
    }
    if (!nullToAbsent || generationTaskId != null) {
      map['generation_task_id'] = Variable<String>(generationTaskId);
    }
    if (!nullToAbsent || rawTranscript != null) {
      map['raw_transcript'] = Variable<String>(rawTranscript);
    }
    if (!nullToAbsent || correctedTranscript != null) {
      map['corrected_transcript'] = Variable<String>(correctedTranscript);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    map['tags_json'] = Variable<String>(tagsJson);
    if (!nullToAbsent || actionContext != null) {
      map['action_context'] = Variable<String>(actionContext);
    }
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    if (!nullToAbsent || openedAt != null) {
      map['opened_at'] = Variable<DateTime>(openedAt);
    }
    if (!nullToAbsent || handledAt != null) {
      map['handled_at'] = Variable<DateTime>(handledAt);
    }
    return map;
  }

  ResearchCapturesCompanion toCompanion(bool nullToAbsent) {
    return ResearchCapturesCompanion(
      id: Value(id),
      participantId: Value(participantId),
      origin: Value(origin),
      sourceType: Value(sourceType),
      originalLocalRecordingId: originalLocalRecordingId == null && nullToAbsent
          ? const Value.absent()
          : Value(originalLocalRecordingId),
      relativePath: Value(relativePath),
      durationMs: Value(durationMs),
      createdAt: Value(createdAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      processingState: Value(processingState),
      inboxState: Value(inboxState),
      jobId: jobId == null && nullToAbsent
          ? const Value.absent()
          : Value(jobId),
      asrSegmentsJson: Value(asrSegmentsJson),
      noteId: noteId == null && nullToAbsent
          ? const Value.absent()
          : Value(noteId),
      generationTaskId: generationTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(generationTaskId),
      rawTranscript: rawTranscript == null && nullToAbsent
          ? const Value.absent()
          : Value(rawTranscript),
      correctedTranscript: correctedTranscript == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedTranscript),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      tagsJson: Value(tagsJson),
      actionContext: actionContext == null && nullToAbsent
          ? const Value.absent()
          : Value(actionContext),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      openedAt: openedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(openedAt),
      handledAt: handledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(handledAt),
    );
  }

  factory ResearchCaptureRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResearchCaptureRow(
      id: serializer.fromJson<String>(json['id']),
      participantId: serializer.fromJson<String>(json['participantId']),
      origin: serializer.fromJson<String>(json['origin']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      originalLocalRecordingId: serializer.fromJson<String?>(
        json['originalLocalRecordingId'],
      ),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      processingState: serializer.fromJson<String>(json['processingState']),
      inboxState: serializer.fromJson<String>(json['inboxState']),
      jobId: serializer.fromJson<String?>(json['jobId']),
      asrSegmentsJson: serializer.fromJson<String>(json['asrSegmentsJson']),
      noteId: serializer.fromJson<String?>(json['noteId']),
      generationTaskId: serializer.fromJson<String?>(json['generationTaskId']),
      rawTranscript: serializer.fromJson<String?>(json['rawTranscript']),
      correctedTranscript: serializer.fromJson<String?>(
        json['correctedTranscript'],
      ),
      title: serializer.fromJson<String?>(json['title']),
      summary: serializer.fromJson<String?>(json['summary']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      actionContext: serializer.fromJson<String?>(json['actionContext']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      openedAt: serializer.fromJson<DateTime?>(json['openedAt']),
      handledAt: serializer.fromJson<DateTime?>(json['handledAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'participantId': serializer.toJson<String>(participantId),
      'origin': serializer.toJson<String>(origin),
      'sourceType': serializer.toJson<String>(sourceType),
      'originalLocalRecordingId': serializer.toJson<String?>(
        originalLocalRecordingId,
      ),
      'relativePath': serializer.toJson<String>(relativePath),
      'durationMs': serializer.toJson<int>(durationMs),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'processingState': serializer.toJson<String>(processingState),
      'inboxState': serializer.toJson<String>(inboxState),
      'jobId': serializer.toJson<String?>(jobId),
      'asrSegmentsJson': serializer.toJson<String>(asrSegmentsJson),
      'noteId': serializer.toJson<String?>(noteId),
      'generationTaskId': serializer.toJson<String?>(generationTaskId),
      'rawTranscript': serializer.toJson<String?>(rawTranscript),
      'correctedTranscript': serializer.toJson<String?>(correctedTranscript),
      'title': serializer.toJson<String?>(title),
      'summary': serializer.toJson<String?>(summary),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'actionContext': serializer.toJson<String?>(actionContext),
      'failureReason': serializer.toJson<String?>(failureReason),
      'openedAt': serializer.toJson<DateTime?>(openedAt),
      'handledAt': serializer.toJson<DateTime?>(handledAt),
    };
  }

  ResearchCaptureRow copyWith({
    String? id,
    String? participantId,
    String? origin,
    String? sourceType,
    Value<String?> originalLocalRecordingId = const Value.absent(),
    String? relativePath,
    int? durationMs,
    DateTime? createdAt,
    Value<DateTime?> completedAt = const Value.absent(),
    String? processingState,
    String? inboxState,
    Value<String?> jobId = const Value.absent(),
    String? asrSegmentsJson,
    Value<String?> noteId = const Value.absent(),
    Value<String?> generationTaskId = const Value.absent(),
    Value<String?> rawTranscript = const Value.absent(),
    Value<String?> correctedTranscript = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> summary = const Value.absent(),
    String? tagsJson,
    Value<String?> actionContext = const Value.absent(),
    Value<String?> failureReason = const Value.absent(),
    Value<DateTime?> openedAt = const Value.absent(),
    Value<DateTime?> handledAt = const Value.absent(),
  }) => ResearchCaptureRow(
    id: id ?? this.id,
    participantId: participantId ?? this.participantId,
    origin: origin ?? this.origin,
    sourceType: sourceType ?? this.sourceType,
    originalLocalRecordingId: originalLocalRecordingId.present
        ? originalLocalRecordingId.value
        : this.originalLocalRecordingId,
    relativePath: relativePath ?? this.relativePath,
    durationMs: durationMs ?? this.durationMs,
    createdAt: createdAt ?? this.createdAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    processingState: processingState ?? this.processingState,
    inboxState: inboxState ?? this.inboxState,
    jobId: jobId.present ? jobId.value : this.jobId,
    asrSegmentsJson: asrSegmentsJson ?? this.asrSegmentsJson,
    noteId: noteId.present ? noteId.value : this.noteId,
    generationTaskId: generationTaskId.present
        ? generationTaskId.value
        : this.generationTaskId,
    rawTranscript: rawTranscript.present
        ? rawTranscript.value
        : this.rawTranscript,
    correctedTranscript: correctedTranscript.present
        ? correctedTranscript.value
        : this.correctedTranscript,
    title: title.present ? title.value : this.title,
    summary: summary.present ? summary.value : this.summary,
    tagsJson: tagsJson ?? this.tagsJson,
    actionContext: actionContext.present
        ? actionContext.value
        : this.actionContext,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    openedAt: openedAt.present ? openedAt.value : this.openedAt,
    handledAt: handledAt.present ? handledAt.value : this.handledAt,
  );
  ResearchCaptureRow copyWithCompanion(ResearchCapturesCompanion data) {
    return ResearchCaptureRow(
      id: data.id.present ? data.id.value : this.id,
      participantId: data.participantId.present
          ? data.participantId.value
          : this.participantId,
      origin: data.origin.present ? data.origin.value : this.origin,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      originalLocalRecordingId: data.originalLocalRecordingId.present
          ? data.originalLocalRecordingId.value
          : this.originalLocalRecordingId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      processingState: data.processingState.present
          ? data.processingState.value
          : this.processingState,
      inboxState: data.inboxState.present
          ? data.inboxState.value
          : this.inboxState,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      asrSegmentsJson: data.asrSegmentsJson.present
          ? data.asrSegmentsJson.value
          : this.asrSegmentsJson,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      generationTaskId: data.generationTaskId.present
          ? data.generationTaskId.value
          : this.generationTaskId,
      rawTranscript: data.rawTranscript.present
          ? data.rawTranscript.value
          : this.rawTranscript,
      correctedTranscript: data.correctedTranscript.present
          ? data.correctedTranscript.value
          : this.correctedTranscript,
      title: data.title.present ? data.title.value : this.title,
      summary: data.summary.present ? data.summary.value : this.summary,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      actionContext: data.actionContext.present
          ? data.actionContext.value
          : this.actionContext,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
      handledAt: data.handledAt.present ? data.handledAt.value : this.handledAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResearchCaptureRow(')
          ..write('id: $id, ')
          ..write('participantId: $participantId, ')
          ..write('origin: $origin, ')
          ..write('sourceType: $sourceType, ')
          ..write('originalLocalRecordingId: $originalLocalRecordingId, ')
          ..write('relativePath: $relativePath, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('processingState: $processingState, ')
          ..write('inboxState: $inboxState, ')
          ..write('jobId: $jobId, ')
          ..write('asrSegmentsJson: $asrSegmentsJson, ')
          ..write('noteId: $noteId, ')
          ..write('generationTaskId: $generationTaskId, ')
          ..write('rawTranscript: $rawTranscript, ')
          ..write('correctedTranscript: $correctedTranscript, ')
          ..write('title: $title, ')
          ..write('summary: $summary, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('actionContext: $actionContext, ')
          ..write('failureReason: $failureReason, ')
          ..write('openedAt: $openedAt, ')
          ..write('handledAt: $handledAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    participantId,
    origin,
    sourceType,
    originalLocalRecordingId,
    relativePath,
    durationMs,
    createdAt,
    completedAt,
    processingState,
    inboxState,
    jobId,
    asrSegmentsJson,
    noteId,
    generationTaskId,
    rawTranscript,
    correctedTranscript,
    title,
    summary,
    tagsJson,
    actionContext,
    failureReason,
    openedAt,
    handledAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResearchCaptureRow &&
          other.id == this.id &&
          other.participantId == this.participantId &&
          other.origin == this.origin &&
          other.sourceType == this.sourceType &&
          other.originalLocalRecordingId == this.originalLocalRecordingId &&
          other.relativePath == this.relativePath &&
          other.durationMs == this.durationMs &&
          other.createdAt == this.createdAt &&
          other.completedAt == this.completedAt &&
          other.processingState == this.processingState &&
          other.inboxState == this.inboxState &&
          other.jobId == this.jobId &&
          other.asrSegmentsJson == this.asrSegmentsJson &&
          other.noteId == this.noteId &&
          other.generationTaskId == this.generationTaskId &&
          other.rawTranscript == this.rawTranscript &&
          other.correctedTranscript == this.correctedTranscript &&
          other.title == this.title &&
          other.summary == this.summary &&
          other.tagsJson == this.tagsJson &&
          other.actionContext == this.actionContext &&
          other.failureReason == this.failureReason &&
          other.openedAt == this.openedAt &&
          other.handledAt == this.handledAt);
}

class ResearchCapturesCompanion extends UpdateCompanion<ResearchCaptureRow> {
  final Value<String> id;
  final Value<String> participantId;
  final Value<String> origin;
  final Value<String> sourceType;
  final Value<String?> originalLocalRecordingId;
  final Value<String> relativePath;
  final Value<int> durationMs;
  final Value<DateTime> createdAt;
  final Value<DateTime?> completedAt;
  final Value<String> processingState;
  final Value<String> inboxState;
  final Value<String?> jobId;
  final Value<String> asrSegmentsJson;
  final Value<String?> noteId;
  final Value<String?> generationTaskId;
  final Value<String?> rawTranscript;
  final Value<String?> correctedTranscript;
  final Value<String?> title;
  final Value<String?> summary;
  final Value<String> tagsJson;
  final Value<String?> actionContext;
  final Value<String?> failureReason;
  final Value<DateTime?> openedAt;
  final Value<DateTime?> handledAt;
  final Value<int> rowid;
  const ResearchCapturesCompanion({
    this.id = const Value.absent(),
    this.participantId = const Value.absent(),
    this.origin = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.originalLocalRecordingId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.processingState = const Value.absent(),
    this.inboxState = const Value.absent(),
    this.jobId = const Value.absent(),
    this.asrSegmentsJson = const Value.absent(),
    this.noteId = const Value.absent(),
    this.generationTaskId = const Value.absent(),
    this.rawTranscript = const Value.absent(),
    this.correctedTranscript = const Value.absent(),
    this.title = const Value.absent(),
    this.summary = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.actionContext = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.handledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResearchCapturesCompanion.insert({
    required String id,
    required String participantId,
    required String origin,
    required String sourceType,
    this.originalLocalRecordingId = const Value.absent(),
    required String relativePath,
    required int durationMs,
    required DateTime createdAt,
    this.completedAt = const Value.absent(),
    required String processingState,
    required String inboxState,
    this.jobId = const Value.absent(),
    this.asrSegmentsJson = const Value.absent(),
    this.noteId = const Value.absent(),
    this.generationTaskId = const Value.absent(),
    this.rawTranscript = const Value.absent(),
    this.correctedTranscript = const Value.absent(),
    this.title = const Value.absent(),
    this.summary = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.actionContext = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.handledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       participantId = Value(participantId),
       origin = Value(origin),
       sourceType = Value(sourceType),
       relativePath = Value(relativePath),
       durationMs = Value(durationMs),
       createdAt = Value(createdAt),
       processingState = Value(processingState),
       inboxState = Value(inboxState);
  static Insertable<ResearchCaptureRow> custom({
    Expression<String>? id,
    Expression<String>? participantId,
    Expression<String>? origin,
    Expression<String>? sourceType,
    Expression<String>? originalLocalRecordingId,
    Expression<String>? relativePath,
    Expression<int>? durationMs,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? completedAt,
    Expression<String>? processingState,
    Expression<String>? inboxState,
    Expression<String>? jobId,
    Expression<String>? asrSegmentsJson,
    Expression<String>? noteId,
    Expression<String>? generationTaskId,
    Expression<String>? rawTranscript,
    Expression<String>? correctedTranscript,
    Expression<String>? title,
    Expression<String>? summary,
    Expression<String>? tagsJson,
    Expression<String>? actionContext,
    Expression<String>? failureReason,
    Expression<DateTime>? openedAt,
    Expression<DateTime>? handledAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (participantId != null) 'participant_id': participantId,
      if (origin != null) 'origin': origin,
      if (sourceType != null) 'source_type': sourceType,
      if (originalLocalRecordingId != null)
        'original_local_recording_id': originalLocalRecordingId,
      if (relativePath != null) 'relative_path': relativePath,
      if (durationMs != null) 'duration_ms': durationMs,
      if (createdAt != null) 'created_at': createdAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (processingState != null) 'processing_state': processingState,
      if (inboxState != null) 'inbox_state': inboxState,
      if (jobId != null) 'job_id': jobId,
      if (asrSegmentsJson != null) 'asr_segments_json': asrSegmentsJson,
      if (noteId != null) 'note_id': noteId,
      if (generationTaskId != null) 'generation_task_id': generationTaskId,
      if (rawTranscript != null) 'raw_transcript': rawTranscript,
      if (correctedTranscript != null)
        'corrected_transcript': correctedTranscript,
      if (title != null) 'title': title,
      if (summary != null) 'summary': summary,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (actionContext != null) 'action_context': actionContext,
      if (failureReason != null) 'failure_reason': failureReason,
      if (openedAt != null) 'opened_at': openedAt,
      if (handledAt != null) 'handled_at': handledAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResearchCapturesCompanion copyWith({
    Value<String>? id,
    Value<String>? participantId,
    Value<String>? origin,
    Value<String>? sourceType,
    Value<String?>? originalLocalRecordingId,
    Value<String>? relativePath,
    Value<int>? durationMs,
    Value<DateTime>? createdAt,
    Value<DateTime?>? completedAt,
    Value<String>? processingState,
    Value<String>? inboxState,
    Value<String?>? jobId,
    Value<String>? asrSegmentsJson,
    Value<String?>? noteId,
    Value<String?>? generationTaskId,
    Value<String?>? rawTranscript,
    Value<String?>? correctedTranscript,
    Value<String?>? title,
    Value<String?>? summary,
    Value<String>? tagsJson,
    Value<String?>? actionContext,
    Value<String?>? failureReason,
    Value<DateTime?>? openedAt,
    Value<DateTime?>? handledAt,
    Value<int>? rowid,
  }) {
    return ResearchCapturesCompanion(
      id: id ?? this.id,
      participantId: participantId ?? this.participantId,
      origin: origin ?? this.origin,
      sourceType: sourceType ?? this.sourceType,
      originalLocalRecordingId:
          originalLocalRecordingId ?? this.originalLocalRecordingId,
      relativePath: relativePath ?? this.relativePath,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      processingState: processingState ?? this.processingState,
      inboxState: inboxState ?? this.inboxState,
      jobId: jobId ?? this.jobId,
      asrSegmentsJson: asrSegmentsJson ?? this.asrSegmentsJson,
      noteId: noteId ?? this.noteId,
      generationTaskId: generationTaskId ?? this.generationTaskId,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      correctedTranscript: correctedTranscript ?? this.correctedTranscript,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      tagsJson: tagsJson ?? this.tagsJson,
      actionContext: actionContext ?? this.actionContext,
      failureReason: failureReason ?? this.failureReason,
      openedAt: openedAt ?? this.openedAt,
      handledAt: handledAt ?? this.handledAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (participantId.present) {
      map['participant_id'] = Variable<String>(participantId.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (originalLocalRecordingId.present) {
      map['original_local_recording_id'] = Variable<String>(
        originalLocalRecordingId.value,
      );
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (processingState.present) {
      map['processing_state'] = Variable<String>(processingState.value);
    }
    if (inboxState.present) {
      map['inbox_state'] = Variable<String>(inboxState.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (asrSegmentsJson.present) {
      map['asr_segments_json'] = Variable<String>(asrSegmentsJson.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (generationTaskId.present) {
      map['generation_task_id'] = Variable<String>(generationTaskId.value);
    }
    if (rawTranscript.present) {
      map['raw_transcript'] = Variable<String>(rawTranscript.value);
    }
    if (correctedTranscript.present) {
      map['corrected_transcript'] = Variable<String>(correctedTranscript.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (actionContext.present) {
      map['action_context'] = Variable<String>(actionContext.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<DateTime>(openedAt.value);
    }
    if (handledAt.present) {
      map['handled_at'] = Variable<DateTime>(handledAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResearchCapturesCompanion(')
          ..write('id: $id, ')
          ..write('participantId: $participantId, ')
          ..write('origin: $origin, ')
          ..write('sourceType: $sourceType, ')
          ..write('originalLocalRecordingId: $originalLocalRecordingId, ')
          ..write('relativePath: $relativePath, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('processingState: $processingState, ')
          ..write('inboxState: $inboxState, ')
          ..write('jobId: $jobId, ')
          ..write('asrSegmentsJson: $asrSegmentsJson, ')
          ..write('noteId: $noteId, ')
          ..write('generationTaskId: $generationTaskId, ')
          ..write('rawTranscript: $rawTranscript, ')
          ..write('correctedTranscript: $correctedTranscript, ')
          ..write('title: $title, ')
          ..write('summary: $summary, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('actionContext: $actionContext, ')
          ..write('failureReason: $failureReason, ')
          ..write('openedAt: $openedAt, ')
          ..write('handledAt: $handledAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ResearchEventsTable extends ResearchEvents
    with TableInfo<$ResearchEventsTable, ResearchEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResearchEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _participantIdMeta = const VerificationMeta(
    'participantId',
  );
  @override
  late final GeneratedColumn<String> participantId = GeneratedColumn<String>(
    'participant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _captureIdMeta = const VerificationMeta(
    'captureId',
  );
  @override
  late final GeneratedColumn<String> captureId = GeneratedColumn<String>(
    'capture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
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
  static const VerificationMeta _processingStateMeta = const VerificationMeta(
    'processingState',
  );
  @override
  late final GeneratedColumn<String> processingState = GeneratedColumn<String>(
    'processing_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationBucketMeta = const VerificationMeta(
    'durationBucket',
  );
  @override
  late final GeneratedColumn<String> durationBucket = GeneratedColumn<String>(
    'duration_bucket',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _qualityFeedbackMeta = const VerificationMeta(
    'qualityFeedback',
  );
  @override
  late final GeneratedColumn<bool> qualityFeedback = GeneratedColumn<bool>(
    'quality_feedback',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("quality_feedback" IN (0, 1))',
    ),
  );
  static const VerificationMeta _dailyUnderstandingMeta =
      const VerificationMeta('dailyUnderstanding');
  @override
  late final GeneratedColumn<bool> dailyUnderstanding = GeneratedColumn<bool>(
    'daily_understanding',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("daily_understanding" IN (0, 1))',
    ),
  );
  static const VerificationMeta _elapsedMillisecondsMeta =
      const VerificationMeta('elapsedMilliseconds');
  @override
  late final GeneratedColumn<int> elapsedMilliseconds = GeneratedColumn<int>(
    'elapsed_milliseconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    participantId,
    captureId,
    type,
    occurredAt,
    processingState,
    durationBucket,
    action,
    qualityFeedback,
    dailyUnderstanding,
    elapsedMilliseconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'research_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResearchEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('participant_id')) {
      context.handle(
        _participantIdMeta,
        participantId.isAcceptableOrUnknown(
          data['participant_id']!,
          _participantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_participantIdMeta);
    }
    if (data.containsKey('capture_id')) {
      context.handle(
        _captureIdMeta,
        captureId.isAcceptableOrUnknown(data['capture_id']!, _captureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_captureIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('processing_state')) {
      context.handle(
        _processingStateMeta,
        processingState.isAcceptableOrUnknown(
          data['processing_state']!,
          _processingStateMeta,
        ),
      );
    }
    if (data.containsKey('duration_bucket')) {
      context.handle(
        _durationBucketMeta,
        durationBucket.isAcceptableOrUnknown(
          data['duration_bucket']!,
          _durationBucketMeta,
        ),
      );
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    }
    if (data.containsKey('quality_feedback')) {
      context.handle(
        _qualityFeedbackMeta,
        qualityFeedback.isAcceptableOrUnknown(
          data['quality_feedback']!,
          _qualityFeedbackMeta,
        ),
      );
    }
    if (data.containsKey('daily_understanding')) {
      context.handle(
        _dailyUnderstandingMeta,
        dailyUnderstanding.isAcceptableOrUnknown(
          data['daily_understanding']!,
          _dailyUnderstandingMeta,
        ),
      );
    }
    if (data.containsKey('elapsed_milliseconds')) {
      context.handle(
        _elapsedMillisecondsMeta,
        elapsedMilliseconds.isAcceptableOrUnknown(
          data['elapsed_milliseconds']!,
          _elapsedMillisecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ResearchEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResearchEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      participantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participant_id'],
      )!,
      captureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capture_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      processingState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_state'],
      ),
      durationBucket: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}duration_bucket'],
      ),
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      ),
      qualityFeedback: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}quality_feedback'],
      ),
      dailyUnderstanding: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}daily_understanding'],
      ),
      elapsedMilliseconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_milliseconds'],
      ),
    );
  }

  @override
  $ResearchEventsTable createAlias(String alias) {
    return $ResearchEventsTable(attachedDatabase, alias);
  }
}

class ResearchEventRow extends DataClass
    implements Insertable<ResearchEventRow> {
  final String id;
  final String participantId;
  final String captureId;
  final String type;
  final DateTime occurredAt;
  final String? processingState;
  final String? durationBucket;
  final String? action;
  final bool? qualityFeedback;
  final bool? dailyUnderstanding;
  final int? elapsedMilliseconds;
  const ResearchEventRow({
    required this.id,
    required this.participantId,
    required this.captureId,
    required this.type,
    required this.occurredAt,
    this.processingState,
    this.durationBucket,
    this.action,
    this.qualityFeedback,
    this.dailyUnderstanding,
    this.elapsedMilliseconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['participant_id'] = Variable<String>(participantId);
    map['capture_id'] = Variable<String>(captureId);
    map['type'] = Variable<String>(type);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    if (!nullToAbsent || processingState != null) {
      map['processing_state'] = Variable<String>(processingState);
    }
    if (!nullToAbsent || durationBucket != null) {
      map['duration_bucket'] = Variable<String>(durationBucket);
    }
    if (!nullToAbsent || action != null) {
      map['action'] = Variable<String>(action);
    }
    if (!nullToAbsent || qualityFeedback != null) {
      map['quality_feedback'] = Variable<bool>(qualityFeedback);
    }
    if (!nullToAbsent || dailyUnderstanding != null) {
      map['daily_understanding'] = Variable<bool>(dailyUnderstanding);
    }
    if (!nullToAbsent || elapsedMilliseconds != null) {
      map['elapsed_milliseconds'] = Variable<int>(elapsedMilliseconds);
    }
    return map;
  }

  ResearchEventsCompanion toCompanion(bool nullToAbsent) {
    return ResearchEventsCompanion(
      id: Value(id),
      participantId: Value(participantId),
      captureId: Value(captureId),
      type: Value(type),
      occurredAt: Value(occurredAt),
      processingState: processingState == null && nullToAbsent
          ? const Value.absent()
          : Value(processingState),
      durationBucket: durationBucket == null && nullToAbsent
          ? const Value.absent()
          : Value(durationBucket),
      action: action == null && nullToAbsent
          ? const Value.absent()
          : Value(action),
      qualityFeedback: qualityFeedback == null && nullToAbsent
          ? const Value.absent()
          : Value(qualityFeedback),
      dailyUnderstanding: dailyUnderstanding == null && nullToAbsent
          ? const Value.absent()
          : Value(dailyUnderstanding),
      elapsedMilliseconds: elapsedMilliseconds == null && nullToAbsent
          ? const Value.absent()
          : Value(elapsedMilliseconds),
    );
  }

  factory ResearchEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResearchEventRow(
      id: serializer.fromJson<String>(json['id']),
      participantId: serializer.fromJson<String>(json['participantId']),
      captureId: serializer.fromJson<String>(json['captureId']),
      type: serializer.fromJson<String>(json['type']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      processingState: serializer.fromJson<String?>(json['processingState']),
      durationBucket: serializer.fromJson<String?>(json['durationBucket']),
      action: serializer.fromJson<String?>(json['action']),
      qualityFeedback: serializer.fromJson<bool?>(json['qualityFeedback']),
      dailyUnderstanding: serializer.fromJson<bool?>(
        json['dailyUnderstanding'],
      ),
      elapsedMilliseconds: serializer.fromJson<int?>(
        json['elapsedMilliseconds'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'participantId': serializer.toJson<String>(participantId),
      'captureId': serializer.toJson<String>(captureId),
      'type': serializer.toJson<String>(type),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'processingState': serializer.toJson<String?>(processingState),
      'durationBucket': serializer.toJson<String?>(durationBucket),
      'action': serializer.toJson<String?>(action),
      'qualityFeedback': serializer.toJson<bool?>(qualityFeedback),
      'dailyUnderstanding': serializer.toJson<bool?>(dailyUnderstanding),
      'elapsedMilliseconds': serializer.toJson<int?>(elapsedMilliseconds),
    };
  }

  ResearchEventRow copyWith({
    String? id,
    String? participantId,
    String? captureId,
    String? type,
    DateTime? occurredAt,
    Value<String?> processingState = const Value.absent(),
    Value<String?> durationBucket = const Value.absent(),
    Value<String?> action = const Value.absent(),
    Value<bool?> qualityFeedback = const Value.absent(),
    Value<bool?> dailyUnderstanding = const Value.absent(),
    Value<int?> elapsedMilliseconds = const Value.absent(),
  }) => ResearchEventRow(
    id: id ?? this.id,
    participantId: participantId ?? this.participantId,
    captureId: captureId ?? this.captureId,
    type: type ?? this.type,
    occurredAt: occurredAt ?? this.occurredAt,
    processingState: processingState.present
        ? processingState.value
        : this.processingState,
    durationBucket: durationBucket.present
        ? durationBucket.value
        : this.durationBucket,
    action: action.present ? action.value : this.action,
    qualityFeedback: qualityFeedback.present
        ? qualityFeedback.value
        : this.qualityFeedback,
    dailyUnderstanding: dailyUnderstanding.present
        ? dailyUnderstanding.value
        : this.dailyUnderstanding,
    elapsedMilliseconds: elapsedMilliseconds.present
        ? elapsedMilliseconds.value
        : this.elapsedMilliseconds,
  );
  ResearchEventRow copyWithCompanion(ResearchEventsCompanion data) {
    return ResearchEventRow(
      id: data.id.present ? data.id.value : this.id,
      participantId: data.participantId.present
          ? data.participantId.value
          : this.participantId,
      captureId: data.captureId.present ? data.captureId.value : this.captureId,
      type: data.type.present ? data.type.value : this.type,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      processingState: data.processingState.present
          ? data.processingState.value
          : this.processingState,
      durationBucket: data.durationBucket.present
          ? data.durationBucket.value
          : this.durationBucket,
      action: data.action.present ? data.action.value : this.action,
      qualityFeedback: data.qualityFeedback.present
          ? data.qualityFeedback.value
          : this.qualityFeedback,
      dailyUnderstanding: data.dailyUnderstanding.present
          ? data.dailyUnderstanding.value
          : this.dailyUnderstanding,
      elapsedMilliseconds: data.elapsedMilliseconds.present
          ? data.elapsedMilliseconds.value
          : this.elapsedMilliseconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResearchEventRow(')
          ..write('id: $id, ')
          ..write('participantId: $participantId, ')
          ..write('captureId: $captureId, ')
          ..write('type: $type, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('processingState: $processingState, ')
          ..write('durationBucket: $durationBucket, ')
          ..write('action: $action, ')
          ..write('qualityFeedback: $qualityFeedback, ')
          ..write('dailyUnderstanding: $dailyUnderstanding, ')
          ..write('elapsedMilliseconds: $elapsedMilliseconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    participantId,
    captureId,
    type,
    occurredAt,
    processingState,
    durationBucket,
    action,
    qualityFeedback,
    dailyUnderstanding,
    elapsedMilliseconds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResearchEventRow &&
          other.id == this.id &&
          other.participantId == this.participantId &&
          other.captureId == this.captureId &&
          other.type == this.type &&
          other.occurredAt == this.occurredAt &&
          other.processingState == this.processingState &&
          other.durationBucket == this.durationBucket &&
          other.action == this.action &&
          other.qualityFeedback == this.qualityFeedback &&
          other.dailyUnderstanding == this.dailyUnderstanding &&
          other.elapsedMilliseconds == this.elapsedMilliseconds);
}

class ResearchEventsCompanion extends UpdateCompanion<ResearchEventRow> {
  final Value<String> id;
  final Value<String> participantId;
  final Value<String> captureId;
  final Value<String> type;
  final Value<DateTime> occurredAt;
  final Value<String?> processingState;
  final Value<String?> durationBucket;
  final Value<String?> action;
  final Value<bool?> qualityFeedback;
  final Value<bool?> dailyUnderstanding;
  final Value<int?> elapsedMilliseconds;
  final Value<int> rowid;
  const ResearchEventsCompanion({
    this.id = const Value.absent(),
    this.participantId = const Value.absent(),
    this.captureId = const Value.absent(),
    this.type = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.processingState = const Value.absent(),
    this.durationBucket = const Value.absent(),
    this.action = const Value.absent(),
    this.qualityFeedback = const Value.absent(),
    this.dailyUnderstanding = const Value.absent(),
    this.elapsedMilliseconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResearchEventsCompanion.insert({
    required String id,
    required String participantId,
    required String captureId,
    required String type,
    required DateTime occurredAt,
    this.processingState = const Value.absent(),
    this.durationBucket = const Value.absent(),
    this.action = const Value.absent(),
    this.qualityFeedback = const Value.absent(),
    this.dailyUnderstanding = const Value.absent(),
    this.elapsedMilliseconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       participantId = Value(participantId),
       captureId = Value(captureId),
       type = Value(type),
       occurredAt = Value(occurredAt);
  static Insertable<ResearchEventRow> custom({
    Expression<String>? id,
    Expression<String>? participantId,
    Expression<String>? captureId,
    Expression<String>? type,
    Expression<DateTime>? occurredAt,
    Expression<String>? processingState,
    Expression<String>? durationBucket,
    Expression<String>? action,
    Expression<bool>? qualityFeedback,
    Expression<bool>? dailyUnderstanding,
    Expression<int>? elapsedMilliseconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (participantId != null) 'participant_id': participantId,
      if (captureId != null) 'capture_id': captureId,
      if (type != null) 'type': type,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (processingState != null) 'processing_state': processingState,
      if (durationBucket != null) 'duration_bucket': durationBucket,
      if (action != null) 'action': action,
      if (qualityFeedback != null) 'quality_feedback': qualityFeedback,
      if (dailyUnderstanding != null) 'daily_understanding': dailyUnderstanding,
      if (elapsedMilliseconds != null)
        'elapsed_milliseconds': elapsedMilliseconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResearchEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? participantId,
    Value<String>? captureId,
    Value<String>? type,
    Value<DateTime>? occurredAt,
    Value<String?>? processingState,
    Value<String?>? durationBucket,
    Value<String?>? action,
    Value<bool?>? qualityFeedback,
    Value<bool?>? dailyUnderstanding,
    Value<int?>? elapsedMilliseconds,
    Value<int>? rowid,
  }) {
    return ResearchEventsCompanion(
      id: id ?? this.id,
      participantId: participantId ?? this.participantId,
      captureId: captureId ?? this.captureId,
      type: type ?? this.type,
      occurredAt: occurredAt ?? this.occurredAt,
      processingState: processingState ?? this.processingState,
      durationBucket: durationBucket ?? this.durationBucket,
      action: action ?? this.action,
      qualityFeedback: qualityFeedback ?? this.qualityFeedback,
      dailyUnderstanding: dailyUnderstanding ?? this.dailyUnderstanding,
      elapsedMilliseconds: elapsedMilliseconds ?? this.elapsedMilliseconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (participantId.present) {
      map['participant_id'] = Variable<String>(participantId.value);
    }
    if (captureId.present) {
      map['capture_id'] = Variable<String>(captureId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (processingState.present) {
      map['processing_state'] = Variable<String>(processingState.value);
    }
    if (durationBucket.present) {
      map['duration_bucket'] = Variable<String>(durationBucket.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (qualityFeedback.present) {
      map['quality_feedback'] = Variable<bool>(qualityFeedback.value);
    }
    if (dailyUnderstanding.present) {
      map['daily_understanding'] = Variable<bool>(dailyUnderstanding.value);
    }
    if (elapsedMilliseconds.present) {
      map['elapsed_milliseconds'] = Variable<int>(elapsedMilliseconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResearchEventsCompanion(')
          ..write('id: $id, ')
          ..write('participantId: $participantId, ')
          ..write('captureId: $captureId, ')
          ..write('type: $type, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('processingState: $processingState, ')
          ..write('durationBucket: $durationBucket, ')
          ..write('action: $action, ')
          ..write('qualityFeedback: $qualityFeedback, ')
          ..write('dailyUnderstanding: $dailyUnderstanding, ')
          ..write('elapsedMilliseconds: $elapsedMilliseconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ResearchAggregatesTable extends ResearchAggregates
    with TableInfo<$ResearchAggregatesTable, ResearchAggregateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResearchAggregatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _participantIdMeta = const VerificationMeta(
    'participantId',
  );
  @override
  late final GeneratedColumn<String> participantId = GeneratedColumn<String>(
    'participant_id',
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _captureCountMeta = const VerificationMeta(
    'captureCount',
  );
  @override
  late final GeneratedColumn<int> captureCount = GeneratedColumn<int>(
    'capture_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _handledCountMeta = const VerificationMeta(
    'handledCount',
  );
  @override
  late final GeneratedColumn<int> handledCount = GeneratedColumn<int>(
    'handled_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _usefulReuseCountMeta = const VerificationMeta(
    'usefulReuseCount',
  );
  @override
  late final GeneratedColumn<int> usefulReuseCount = GeneratedColumn<int>(
    'useful_reuse_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _accurateFeedbackCountMeta =
      const VerificationMeta('accurateFeedbackCount');
  @override
  late final GeneratedColumn<int> accurateFeedbackCount = GeneratedColumn<int>(
    'accurate_feedback_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _inaccurateFeedbackCountMeta =
      const VerificationMeta('inaccurateFeedbackCount');
  @override
  late final GeneratedColumn<int> inaccurateFeedbackCount =
      GeneratedColumn<int>(
        'inaccurate_feedback_count',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _understoodCountMeta = const VerificationMeta(
    'understoodCount',
  );
  @override
  late final GeneratedColumn<int> understoodCount = GeneratedColumn<int>(
    'understood_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _notUnderstoodCountMeta =
      const VerificationMeta('notUnderstoodCount');
  @override
  late final GeneratedColumn<int> notUnderstoodCount = GeneratedColumn<int>(
    'not_understood_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    participantId,
    createdAt,
    updatedAt,
    captureCount,
    handledCount,
    usefulReuseCount,
    accurateFeedbackCount,
    inaccurateFeedbackCount,
    understoodCount,
    notUnderstoodCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'research_aggregates';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResearchAggregateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('participant_id')) {
      context.handle(
        _participantIdMeta,
        participantId.isAcceptableOrUnknown(
          data['participant_id']!,
          _participantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_participantIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('capture_count')) {
      context.handle(
        _captureCountMeta,
        captureCount.isAcceptableOrUnknown(
          data['capture_count']!,
          _captureCountMeta,
        ),
      );
    }
    if (data.containsKey('handled_count')) {
      context.handle(
        _handledCountMeta,
        handledCount.isAcceptableOrUnknown(
          data['handled_count']!,
          _handledCountMeta,
        ),
      );
    }
    if (data.containsKey('useful_reuse_count')) {
      context.handle(
        _usefulReuseCountMeta,
        usefulReuseCount.isAcceptableOrUnknown(
          data['useful_reuse_count']!,
          _usefulReuseCountMeta,
        ),
      );
    }
    if (data.containsKey('accurate_feedback_count')) {
      context.handle(
        _accurateFeedbackCountMeta,
        accurateFeedbackCount.isAcceptableOrUnknown(
          data['accurate_feedback_count']!,
          _accurateFeedbackCountMeta,
        ),
      );
    }
    if (data.containsKey('inaccurate_feedback_count')) {
      context.handle(
        _inaccurateFeedbackCountMeta,
        inaccurateFeedbackCount.isAcceptableOrUnknown(
          data['inaccurate_feedback_count']!,
          _inaccurateFeedbackCountMeta,
        ),
      );
    }
    if (data.containsKey('understood_count')) {
      context.handle(
        _understoodCountMeta,
        understoodCount.isAcceptableOrUnknown(
          data['understood_count']!,
          _understoodCountMeta,
        ),
      );
    }
    if (data.containsKey('not_understood_count')) {
      context.handle(
        _notUnderstoodCountMeta,
        notUnderstoodCount.isAcceptableOrUnknown(
          data['not_understood_count']!,
          _notUnderstoodCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {participantId};
  @override
  ResearchAggregateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResearchAggregateRow(
      participantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participant_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      captureCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}capture_count'],
      )!,
      handledCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}handled_count'],
      )!,
      usefulReuseCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}useful_reuse_count'],
      )!,
      accurateFeedbackCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accurate_feedback_count'],
      )!,
      inaccurateFeedbackCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}inaccurate_feedback_count'],
      )!,
      understoodCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}understood_count'],
      )!,
      notUnderstoodCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}not_understood_count'],
      )!,
    );
  }

  @override
  $ResearchAggregatesTable createAlias(String alias) {
    return $ResearchAggregatesTable(attachedDatabase, alias);
  }
}

class ResearchAggregateRow extends DataClass
    implements Insertable<ResearchAggregateRow> {
  final String participantId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int captureCount;
  final int handledCount;
  final int usefulReuseCount;
  final int accurateFeedbackCount;
  final int inaccurateFeedbackCount;
  final int understoodCount;
  final int notUnderstoodCount;
  const ResearchAggregateRow({
    required this.participantId,
    required this.createdAt,
    required this.updatedAt,
    required this.captureCount,
    required this.handledCount,
    required this.usefulReuseCount,
    required this.accurateFeedbackCount,
    required this.inaccurateFeedbackCount,
    required this.understoodCount,
    required this.notUnderstoodCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['participant_id'] = Variable<String>(participantId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['capture_count'] = Variable<int>(captureCount);
    map['handled_count'] = Variable<int>(handledCount);
    map['useful_reuse_count'] = Variable<int>(usefulReuseCount);
    map['accurate_feedback_count'] = Variable<int>(accurateFeedbackCount);
    map['inaccurate_feedback_count'] = Variable<int>(inaccurateFeedbackCount);
    map['understood_count'] = Variable<int>(understoodCount);
    map['not_understood_count'] = Variable<int>(notUnderstoodCount);
    return map;
  }

  ResearchAggregatesCompanion toCompanion(bool nullToAbsent) {
    return ResearchAggregatesCompanion(
      participantId: Value(participantId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      captureCount: Value(captureCount),
      handledCount: Value(handledCount),
      usefulReuseCount: Value(usefulReuseCount),
      accurateFeedbackCount: Value(accurateFeedbackCount),
      inaccurateFeedbackCount: Value(inaccurateFeedbackCount),
      understoodCount: Value(understoodCount),
      notUnderstoodCount: Value(notUnderstoodCount),
    );
  }

  factory ResearchAggregateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResearchAggregateRow(
      participantId: serializer.fromJson<String>(json['participantId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      captureCount: serializer.fromJson<int>(json['captureCount']),
      handledCount: serializer.fromJson<int>(json['handledCount']),
      usefulReuseCount: serializer.fromJson<int>(json['usefulReuseCount']),
      accurateFeedbackCount: serializer.fromJson<int>(
        json['accurateFeedbackCount'],
      ),
      inaccurateFeedbackCount: serializer.fromJson<int>(
        json['inaccurateFeedbackCount'],
      ),
      understoodCount: serializer.fromJson<int>(json['understoodCount']),
      notUnderstoodCount: serializer.fromJson<int>(json['notUnderstoodCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'participantId': serializer.toJson<String>(participantId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'captureCount': serializer.toJson<int>(captureCount),
      'handledCount': serializer.toJson<int>(handledCount),
      'usefulReuseCount': serializer.toJson<int>(usefulReuseCount),
      'accurateFeedbackCount': serializer.toJson<int>(accurateFeedbackCount),
      'inaccurateFeedbackCount': serializer.toJson<int>(
        inaccurateFeedbackCount,
      ),
      'understoodCount': serializer.toJson<int>(understoodCount),
      'notUnderstoodCount': serializer.toJson<int>(notUnderstoodCount),
    };
  }

  ResearchAggregateRow copyWith({
    String? participantId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? captureCount,
    int? handledCount,
    int? usefulReuseCount,
    int? accurateFeedbackCount,
    int? inaccurateFeedbackCount,
    int? understoodCount,
    int? notUnderstoodCount,
  }) => ResearchAggregateRow(
    participantId: participantId ?? this.participantId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    captureCount: captureCount ?? this.captureCount,
    handledCount: handledCount ?? this.handledCount,
    usefulReuseCount: usefulReuseCount ?? this.usefulReuseCount,
    accurateFeedbackCount: accurateFeedbackCount ?? this.accurateFeedbackCount,
    inaccurateFeedbackCount:
        inaccurateFeedbackCount ?? this.inaccurateFeedbackCount,
    understoodCount: understoodCount ?? this.understoodCount,
    notUnderstoodCount: notUnderstoodCount ?? this.notUnderstoodCount,
  );
  ResearchAggregateRow copyWithCompanion(ResearchAggregatesCompanion data) {
    return ResearchAggregateRow(
      participantId: data.participantId.present
          ? data.participantId.value
          : this.participantId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      captureCount: data.captureCount.present
          ? data.captureCount.value
          : this.captureCount,
      handledCount: data.handledCount.present
          ? data.handledCount.value
          : this.handledCount,
      usefulReuseCount: data.usefulReuseCount.present
          ? data.usefulReuseCount.value
          : this.usefulReuseCount,
      accurateFeedbackCount: data.accurateFeedbackCount.present
          ? data.accurateFeedbackCount.value
          : this.accurateFeedbackCount,
      inaccurateFeedbackCount: data.inaccurateFeedbackCount.present
          ? data.inaccurateFeedbackCount.value
          : this.inaccurateFeedbackCount,
      understoodCount: data.understoodCount.present
          ? data.understoodCount.value
          : this.understoodCount,
      notUnderstoodCount: data.notUnderstoodCount.present
          ? data.notUnderstoodCount.value
          : this.notUnderstoodCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResearchAggregateRow(')
          ..write('participantId: $participantId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('captureCount: $captureCount, ')
          ..write('handledCount: $handledCount, ')
          ..write('usefulReuseCount: $usefulReuseCount, ')
          ..write('accurateFeedbackCount: $accurateFeedbackCount, ')
          ..write('inaccurateFeedbackCount: $inaccurateFeedbackCount, ')
          ..write('understoodCount: $understoodCount, ')
          ..write('notUnderstoodCount: $notUnderstoodCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    participantId,
    createdAt,
    updatedAt,
    captureCount,
    handledCount,
    usefulReuseCount,
    accurateFeedbackCount,
    inaccurateFeedbackCount,
    understoodCount,
    notUnderstoodCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResearchAggregateRow &&
          other.participantId == this.participantId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.captureCount == this.captureCount &&
          other.handledCount == this.handledCount &&
          other.usefulReuseCount == this.usefulReuseCount &&
          other.accurateFeedbackCount == this.accurateFeedbackCount &&
          other.inaccurateFeedbackCount == this.inaccurateFeedbackCount &&
          other.understoodCount == this.understoodCount &&
          other.notUnderstoodCount == this.notUnderstoodCount);
}

class ResearchAggregatesCompanion
    extends UpdateCompanion<ResearchAggregateRow> {
  final Value<String> participantId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> captureCount;
  final Value<int> handledCount;
  final Value<int> usefulReuseCount;
  final Value<int> accurateFeedbackCount;
  final Value<int> inaccurateFeedbackCount;
  final Value<int> understoodCount;
  final Value<int> notUnderstoodCount;
  final Value<int> rowid;
  const ResearchAggregatesCompanion({
    this.participantId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.captureCount = const Value.absent(),
    this.handledCount = const Value.absent(),
    this.usefulReuseCount = const Value.absent(),
    this.accurateFeedbackCount = const Value.absent(),
    this.inaccurateFeedbackCount = const Value.absent(),
    this.understoodCount = const Value.absent(),
    this.notUnderstoodCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResearchAggregatesCompanion.insert({
    required String participantId,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.captureCount = const Value.absent(),
    this.handledCount = const Value.absent(),
    this.usefulReuseCount = const Value.absent(),
    this.accurateFeedbackCount = const Value.absent(),
    this.inaccurateFeedbackCount = const Value.absent(),
    this.understoodCount = const Value.absent(),
    this.notUnderstoodCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : participantId = Value(participantId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ResearchAggregateRow> custom({
    Expression<String>? participantId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? captureCount,
    Expression<int>? handledCount,
    Expression<int>? usefulReuseCount,
    Expression<int>? accurateFeedbackCount,
    Expression<int>? inaccurateFeedbackCount,
    Expression<int>? understoodCount,
    Expression<int>? notUnderstoodCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (participantId != null) 'participant_id': participantId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (captureCount != null) 'capture_count': captureCount,
      if (handledCount != null) 'handled_count': handledCount,
      if (usefulReuseCount != null) 'useful_reuse_count': usefulReuseCount,
      if (accurateFeedbackCount != null)
        'accurate_feedback_count': accurateFeedbackCount,
      if (inaccurateFeedbackCount != null)
        'inaccurate_feedback_count': inaccurateFeedbackCount,
      if (understoodCount != null) 'understood_count': understoodCount,
      if (notUnderstoodCount != null)
        'not_understood_count': notUnderstoodCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResearchAggregatesCompanion copyWith({
    Value<String>? participantId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? captureCount,
    Value<int>? handledCount,
    Value<int>? usefulReuseCount,
    Value<int>? accurateFeedbackCount,
    Value<int>? inaccurateFeedbackCount,
    Value<int>? understoodCount,
    Value<int>? notUnderstoodCount,
    Value<int>? rowid,
  }) {
    return ResearchAggregatesCompanion(
      participantId: participantId ?? this.participantId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      captureCount: captureCount ?? this.captureCount,
      handledCount: handledCount ?? this.handledCount,
      usefulReuseCount: usefulReuseCount ?? this.usefulReuseCount,
      accurateFeedbackCount:
          accurateFeedbackCount ?? this.accurateFeedbackCount,
      inaccurateFeedbackCount:
          inaccurateFeedbackCount ?? this.inaccurateFeedbackCount,
      understoodCount: understoodCount ?? this.understoodCount,
      notUnderstoodCount: notUnderstoodCount ?? this.notUnderstoodCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (participantId.present) {
      map['participant_id'] = Variable<String>(participantId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (captureCount.present) {
      map['capture_count'] = Variable<int>(captureCount.value);
    }
    if (handledCount.present) {
      map['handled_count'] = Variable<int>(handledCount.value);
    }
    if (usefulReuseCount.present) {
      map['useful_reuse_count'] = Variable<int>(usefulReuseCount.value);
    }
    if (accurateFeedbackCount.present) {
      map['accurate_feedback_count'] = Variable<int>(
        accurateFeedbackCount.value,
      );
    }
    if (inaccurateFeedbackCount.present) {
      map['inaccurate_feedback_count'] = Variable<int>(
        inaccurateFeedbackCount.value,
      );
    }
    if (understoodCount.present) {
      map['understood_count'] = Variable<int>(understoodCount.value);
    }
    if (notUnderstoodCount.present) {
      map['not_understood_count'] = Variable<int>(notUnderstoodCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResearchAggregatesCompanion(')
          ..write('participantId: $participantId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('captureCount: $captureCount, ')
          ..write('handledCount: $handledCount, ')
          ..write('usefulReuseCount: $usefulReuseCount, ')
          ..write('accurateFeedbackCount: $accurateFeedbackCount, ')
          ..write('inaccurateFeedbackCount: $inaccurateFeedbackCount, ')
          ..write('understoodCount: $understoodCount, ')
          ..write('notUnderstoodCount: $notUnderstoodCount, ')
          ..write('rowid: $rowid')
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
  late final $LocalRecordingsTable localRecordings = $LocalRecordingsTable(
    this,
  );
  late final $ResearchCapturesTable researchCaptures = $ResearchCapturesTable(
    this,
  );
  late final $ResearchEventsTable researchEvents = $ResearchEventsTable(this);
  late final $ResearchAggregatesTable researchAggregates =
      $ResearchAggregatesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    evidenceBundles,
    sessionEvents,
    localRecordings,
    researchCaptures,
    researchEvents,
    researchAggregates,
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
typedef $$LocalRecordingsTableCreateCompanionBuilder =
    LocalRecordingsCompanion Function({
      required String id,
      required String title,
      required String relativePath,
      required DateTime createdAt,
      Value<DateTime?> completedAt,
      Value<int?> durationMs,
      Value<int?> sizeBytes,
      required String state,
      Value<String?> failureReason,
      Value<int> rowid,
    });
typedef $$LocalRecordingsTableUpdateCompanionBuilder =
    LocalRecordingsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> relativePath,
      Value<DateTime> createdAt,
      Value<DateTime?> completedAt,
      Value<int?> durationMs,
      Value<int?> sizeBytes,
      Value<String> state,
      Value<String?> failureReason,
      Value<int> rowid,
    });

class $$LocalRecordingsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalRecordingsTable> {
  $$LocalRecordingsTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalRecordingsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalRecordingsTable> {
  $$LocalRecordingsTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalRecordingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalRecordingsTable> {
  $$LocalRecordingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );
}

class $$LocalRecordingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalRecordingsTable,
          LocalRecordingRow,
          $$LocalRecordingsTableFilterComposer,
          $$LocalRecordingsTableOrderingComposer,
          $$LocalRecordingsTableAnnotationComposer,
          $$LocalRecordingsTableCreateCompanionBuilder,
          $$LocalRecordingsTableUpdateCompanionBuilder,
          (
            LocalRecordingRow,
            BaseReferences<
              _$AppDatabase,
              $LocalRecordingsTable,
              LocalRecordingRow
            >,
          ),
          LocalRecordingRow,
          PrefetchHooks Function()
        > {
  $$LocalRecordingsTableTableManager(
    _$AppDatabase db,
    $LocalRecordingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRecordingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRecordingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRecordingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalRecordingsCompanion(
                id: id,
                title: title,
                relativePath: relativePath,
                createdAt: createdAt,
                completedAt: completedAt,
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                state: state,
                failureReason: failureReason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String relativePath,
                required DateTime createdAt,
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                required String state,
                Value<String?> failureReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalRecordingsCompanion.insert(
                id: id,
                title: title,
                relativePath: relativePath,
                createdAt: createdAt,
                completedAt: completedAt,
                durationMs: durationMs,
                sizeBytes: sizeBytes,
                state: state,
                failureReason: failureReason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalRecordingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalRecordingsTable,
      LocalRecordingRow,
      $$LocalRecordingsTableFilterComposer,
      $$LocalRecordingsTableOrderingComposer,
      $$LocalRecordingsTableAnnotationComposer,
      $$LocalRecordingsTableCreateCompanionBuilder,
      $$LocalRecordingsTableUpdateCompanionBuilder,
      (
        LocalRecordingRow,
        BaseReferences<_$AppDatabase, $LocalRecordingsTable, LocalRecordingRow>,
      ),
      LocalRecordingRow,
      PrefetchHooks Function()
    >;
typedef $$ResearchCapturesTableCreateCompanionBuilder =
    ResearchCapturesCompanion Function({
      required String id,
      required String participantId,
      required String origin,
      required String sourceType,
      Value<String?> originalLocalRecordingId,
      required String relativePath,
      required int durationMs,
      required DateTime createdAt,
      Value<DateTime?> completedAt,
      required String processingState,
      required String inboxState,
      Value<String?> jobId,
      Value<String> asrSegmentsJson,
      Value<String?> noteId,
      Value<String?> generationTaskId,
      Value<String?> rawTranscript,
      Value<String?> correctedTranscript,
      Value<String?> title,
      Value<String?> summary,
      Value<String> tagsJson,
      Value<String?> actionContext,
      Value<String?> failureReason,
      Value<DateTime?> openedAt,
      Value<DateTime?> handledAt,
      Value<int> rowid,
    });
typedef $$ResearchCapturesTableUpdateCompanionBuilder =
    ResearchCapturesCompanion Function({
      Value<String> id,
      Value<String> participantId,
      Value<String> origin,
      Value<String> sourceType,
      Value<String?> originalLocalRecordingId,
      Value<String> relativePath,
      Value<int> durationMs,
      Value<DateTime> createdAt,
      Value<DateTime?> completedAt,
      Value<String> processingState,
      Value<String> inboxState,
      Value<String?> jobId,
      Value<String> asrSegmentsJson,
      Value<String?> noteId,
      Value<String?> generationTaskId,
      Value<String?> rawTranscript,
      Value<String?> correctedTranscript,
      Value<String?> title,
      Value<String?> summary,
      Value<String> tagsJson,
      Value<String?> actionContext,
      Value<String?> failureReason,
      Value<DateTime?> openedAt,
      Value<DateTime?> handledAt,
      Value<int> rowid,
    });

class $$ResearchCapturesTableFilterComposer
    extends Composer<_$AppDatabase, $ResearchCapturesTable> {
  $$ResearchCapturesTableFilterComposer({
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

  ColumnFilters<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalLocalRecordingId => $composableBuilder(
    column: $table.originalLocalRecordingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processingState => $composableBuilder(
    column: $table.processingState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inboxState => $composableBuilder(
    column: $table.inboxState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get asrSegmentsJson => $composableBuilder(
    column: $table.asrSegmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get generationTaskId => $composableBuilder(
    column: $table.generationTaskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawTranscript => $composableBuilder(
    column: $table.rawTranscript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correctedTranscript => $composableBuilder(
    column: $table.correctedTranscript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actionContext => $composableBuilder(
    column: $table.actionContext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get handledAt => $composableBuilder(
    column: $table.handledAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ResearchCapturesTableOrderingComposer
    extends Composer<_$AppDatabase, $ResearchCapturesTable> {
  $$ResearchCapturesTableOrderingComposer({
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

  ColumnOrderings<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalLocalRecordingId => $composableBuilder(
    column: $table.originalLocalRecordingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processingState => $composableBuilder(
    column: $table.processingState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inboxState => $composableBuilder(
    column: $table.inboxState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get asrSegmentsJson => $composableBuilder(
    column: $table.asrSegmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get generationTaskId => $composableBuilder(
    column: $table.generationTaskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawTranscript => $composableBuilder(
    column: $table.rawTranscript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correctedTranscript => $composableBuilder(
    column: $table.correctedTranscript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actionContext => $composableBuilder(
    column: $table.actionContext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get handledAt => $composableBuilder(
    column: $table.handledAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ResearchCapturesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ResearchCapturesTable> {
  $$ResearchCapturesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalLocalRecordingId => $composableBuilder(
    column: $table.originalLocalRecordingId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processingState => $composableBuilder(
    column: $table.processingState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inboxState => $composableBuilder(
    column: $table.inboxState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get asrSegmentsJson => $composableBuilder(
    column: $table.asrSegmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get generationTaskId => $composableBuilder(
    column: $table.generationTaskId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawTranscript => $composableBuilder(
    column: $table.rawTranscript,
    builder: (column) => column,
  );

  GeneratedColumn<String> get correctedTranscript => $composableBuilder(
    column: $table.correctedTranscript,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get actionContext => $composableBuilder(
    column: $table.actionContext,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get handledAt =>
      $composableBuilder(column: $table.handledAt, builder: (column) => column);
}

class $$ResearchCapturesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ResearchCapturesTable,
          ResearchCaptureRow,
          $$ResearchCapturesTableFilterComposer,
          $$ResearchCapturesTableOrderingComposer,
          $$ResearchCapturesTableAnnotationComposer,
          $$ResearchCapturesTableCreateCompanionBuilder,
          $$ResearchCapturesTableUpdateCompanionBuilder,
          (
            ResearchCaptureRow,
            BaseReferences<
              _$AppDatabase,
              $ResearchCapturesTable,
              ResearchCaptureRow
            >,
          ),
          ResearchCaptureRow,
          PrefetchHooks Function()
        > {
  $$ResearchCapturesTableTableManager(
    _$AppDatabase db,
    $ResearchCapturesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResearchCapturesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResearchCapturesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResearchCapturesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> participantId = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String> sourceType = const Value.absent(),
                Value<String?> originalLocalRecordingId = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String> processingState = const Value.absent(),
                Value<String> inboxState = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                Value<String> asrSegmentsJson = const Value.absent(),
                Value<String?> noteId = const Value.absent(),
                Value<String?> generationTaskId = const Value.absent(),
                Value<String?> rawTranscript = const Value.absent(),
                Value<String?> correctedTranscript = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String?> actionContext = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<DateTime?> openedAt = const Value.absent(),
                Value<DateTime?> handledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResearchCapturesCompanion(
                id: id,
                participantId: participantId,
                origin: origin,
                sourceType: sourceType,
                originalLocalRecordingId: originalLocalRecordingId,
                relativePath: relativePath,
                durationMs: durationMs,
                createdAt: createdAt,
                completedAt: completedAt,
                processingState: processingState,
                inboxState: inboxState,
                jobId: jobId,
                asrSegmentsJson: asrSegmentsJson,
                noteId: noteId,
                generationTaskId: generationTaskId,
                rawTranscript: rawTranscript,
                correctedTranscript: correctedTranscript,
                title: title,
                summary: summary,
                tagsJson: tagsJson,
                actionContext: actionContext,
                failureReason: failureReason,
                openedAt: openedAt,
                handledAt: handledAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String participantId,
                required String origin,
                required String sourceType,
                Value<String?> originalLocalRecordingId = const Value.absent(),
                required String relativePath,
                required int durationMs,
                required DateTime createdAt,
                Value<DateTime?> completedAt = const Value.absent(),
                required String processingState,
                required String inboxState,
                Value<String?> jobId = const Value.absent(),
                Value<String> asrSegmentsJson = const Value.absent(),
                Value<String?> noteId = const Value.absent(),
                Value<String?> generationTaskId = const Value.absent(),
                Value<String?> rawTranscript = const Value.absent(),
                Value<String?> correctedTranscript = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String?> actionContext = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<DateTime?> openedAt = const Value.absent(),
                Value<DateTime?> handledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResearchCapturesCompanion.insert(
                id: id,
                participantId: participantId,
                origin: origin,
                sourceType: sourceType,
                originalLocalRecordingId: originalLocalRecordingId,
                relativePath: relativePath,
                durationMs: durationMs,
                createdAt: createdAt,
                completedAt: completedAt,
                processingState: processingState,
                inboxState: inboxState,
                jobId: jobId,
                asrSegmentsJson: asrSegmentsJson,
                noteId: noteId,
                generationTaskId: generationTaskId,
                rawTranscript: rawTranscript,
                correctedTranscript: correctedTranscript,
                title: title,
                summary: summary,
                tagsJson: tagsJson,
                actionContext: actionContext,
                failureReason: failureReason,
                openedAt: openedAt,
                handledAt: handledAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ResearchCapturesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ResearchCapturesTable,
      ResearchCaptureRow,
      $$ResearchCapturesTableFilterComposer,
      $$ResearchCapturesTableOrderingComposer,
      $$ResearchCapturesTableAnnotationComposer,
      $$ResearchCapturesTableCreateCompanionBuilder,
      $$ResearchCapturesTableUpdateCompanionBuilder,
      (
        ResearchCaptureRow,
        BaseReferences<
          _$AppDatabase,
          $ResearchCapturesTable,
          ResearchCaptureRow
        >,
      ),
      ResearchCaptureRow,
      PrefetchHooks Function()
    >;
typedef $$ResearchEventsTableCreateCompanionBuilder =
    ResearchEventsCompanion Function({
      required String id,
      required String participantId,
      required String captureId,
      required String type,
      required DateTime occurredAt,
      Value<String?> processingState,
      Value<String?> durationBucket,
      Value<String?> action,
      Value<bool?> qualityFeedback,
      Value<bool?> dailyUnderstanding,
      Value<int?> elapsedMilliseconds,
      Value<int> rowid,
    });
typedef $$ResearchEventsTableUpdateCompanionBuilder =
    ResearchEventsCompanion Function({
      Value<String> id,
      Value<String> participantId,
      Value<String> captureId,
      Value<String> type,
      Value<DateTime> occurredAt,
      Value<String?> processingState,
      Value<String?> durationBucket,
      Value<String?> action,
      Value<bool?> qualityFeedback,
      Value<bool?> dailyUnderstanding,
      Value<int?> elapsedMilliseconds,
      Value<int> rowid,
    });

class $$ResearchEventsTableFilterComposer
    extends Composer<_$AppDatabase, $ResearchEventsTable> {
  $$ResearchEventsTableFilterComposer({
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

  ColumnFilters<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get captureId => $composableBuilder(
    column: $table.captureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processingState => $composableBuilder(
    column: $table.processingState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get durationBucket => $composableBuilder(
    column: $table.durationBucket,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get qualityFeedback => $composableBuilder(
    column: $table.qualityFeedback,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dailyUnderstanding => $composableBuilder(
    column: $table.dailyUnderstanding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedMilliseconds => $composableBuilder(
    column: $table.elapsedMilliseconds,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ResearchEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $ResearchEventsTable> {
  $$ResearchEventsTableOrderingComposer({
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

  ColumnOrderings<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get captureId => $composableBuilder(
    column: $table.captureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processingState => $composableBuilder(
    column: $table.processingState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get durationBucket => $composableBuilder(
    column: $table.durationBucket,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get qualityFeedback => $composableBuilder(
    column: $table.qualityFeedback,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dailyUnderstanding => $composableBuilder(
    column: $table.dailyUnderstanding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedMilliseconds => $composableBuilder(
    column: $table.elapsedMilliseconds,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ResearchEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ResearchEventsTable> {
  $$ResearchEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get captureId =>
      $composableBuilder(column: $table.captureId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processingState => $composableBuilder(
    column: $table.processingState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get durationBucket => $composableBuilder(
    column: $table.durationBucket,
    builder: (column) => column,
  );

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<bool> get qualityFeedback => $composableBuilder(
    column: $table.qualityFeedback,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dailyUnderstanding => $composableBuilder(
    column: $table.dailyUnderstanding,
    builder: (column) => column,
  );

  GeneratedColumn<int> get elapsedMilliseconds => $composableBuilder(
    column: $table.elapsedMilliseconds,
    builder: (column) => column,
  );
}

class $$ResearchEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ResearchEventsTable,
          ResearchEventRow,
          $$ResearchEventsTableFilterComposer,
          $$ResearchEventsTableOrderingComposer,
          $$ResearchEventsTableAnnotationComposer,
          $$ResearchEventsTableCreateCompanionBuilder,
          $$ResearchEventsTableUpdateCompanionBuilder,
          (
            ResearchEventRow,
            BaseReferences<
              _$AppDatabase,
              $ResearchEventsTable,
              ResearchEventRow
            >,
          ),
          ResearchEventRow,
          PrefetchHooks Function()
        > {
  $$ResearchEventsTableTableManager(
    _$AppDatabase db,
    $ResearchEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResearchEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResearchEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResearchEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> participantId = const Value.absent(),
                Value<String> captureId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String?> processingState = const Value.absent(),
                Value<String?> durationBucket = const Value.absent(),
                Value<String?> action = const Value.absent(),
                Value<bool?> qualityFeedback = const Value.absent(),
                Value<bool?> dailyUnderstanding = const Value.absent(),
                Value<int?> elapsedMilliseconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResearchEventsCompanion(
                id: id,
                participantId: participantId,
                captureId: captureId,
                type: type,
                occurredAt: occurredAt,
                processingState: processingState,
                durationBucket: durationBucket,
                action: action,
                qualityFeedback: qualityFeedback,
                dailyUnderstanding: dailyUnderstanding,
                elapsedMilliseconds: elapsedMilliseconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String participantId,
                required String captureId,
                required String type,
                required DateTime occurredAt,
                Value<String?> processingState = const Value.absent(),
                Value<String?> durationBucket = const Value.absent(),
                Value<String?> action = const Value.absent(),
                Value<bool?> qualityFeedback = const Value.absent(),
                Value<bool?> dailyUnderstanding = const Value.absent(),
                Value<int?> elapsedMilliseconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResearchEventsCompanion.insert(
                id: id,
                participantId: participantId,
                captureId: captureId,
                type: type,
                occurredAt: occurredAt,
                processingState: processingState,
                durationBucket: durationBucket,
                action: action,
                qualityFeedback: qualityFeedback,
                dailyUnderstanding: dailyUnderstanding,
                elapsedMilliseconds: elapsedMilliseconds,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ResearchEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ResearchEventsTable,
      ResearchEventRow,
      $$ResearchEventsTableFilterComposer,
      $$ResearchEventsTableOrderingComposer,
      $$ResearchEventsTableAnnotationComposer,
      $$ResearchEventsTableCreateCompanionBuilder,
      $$ResearchEventsTableUpdateCompanionBuilder,
      (
        ResearchEventRow,
        BaseReferences<_$AppDatabase, $ResearchEventsTable, ResearchEventRow>,
      ),
      ResearchEventRow,
      PrefetchHooks Function()
    >;
typedef $$ResearchAggregatesTableCreateCompanionBuilder =
    ResearchAggregatesCompanion Function({
      required String participantId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> captureCount,
      Value<int> handledCount,
      Value<int> usefulReuseCount,
      Value<int> accurateFeedbackCount,
      Value<int> inaccurateFeedbackCount,
      Value<int> understoodCount,
      Value<int> notUnderstoodCount,
      Value<int> rowid,
    });
typedef $$ResearchAggregatesTableUpdateCompanionBuilder =
    ResearchAggregatesCompanion Function({
      Value<String> participantId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> captureCount,
      Value<int> handledCount,
      Value<int> usefulReuseCount,
      Value<int> accurateFeedbackCount,
      Value<int> inaccurateFeedbackCount,
      Value<int> understoodCount,
      Value<int> notUnderstoodCount,
      Value<int> rowid,
    });

class $$ResearchAggregatesTableFilterComposer
    extends Composer<_$AppDatabase, $ResearchAggregatesTable> {
  $$ResearchAggregatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get captureCount => $composableBuilder(
    column: $table.captureCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get handledCount => $composableBuilder(
    column: $table.handledCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usefulReuseCount => $composableBuilder(
    column: $table.usefulReuseCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accurateFeedbackCount => $composableBuilder(
    column: $table.accurateFeedbackCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inaccurateFeedbackCount => $composableBuilder(
    column: $table.inaccurateFeedbackCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get understoodCount => $composableBuilder(
    column: $table.understoodCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notUnderstoodCount => $composableBuilder(
    column: $table.notUnderstoodCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ResearchAggregatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ResearchAggregatesTable> {
  $$ResearchAggregatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get captureCount => $composableBuilder(
    column: $table.captureCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get handledCount => $composableBuilder(
    column: $table.handledCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usefulReuseCount => $composableBuilder(
    column: $table.usefulReuseCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accurateFeedbackCount => $composableBuilder(
    column: $table.accurateFeedbackCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inaccurateFeedbackCount => $composableBuilder(
    column: $table.inaccurateFeedbackCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get understoodCount => $composableBuilder(
    column: $table.understoodCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notUnderstoodCount => $composableBuilder(
    column: $table.notUnderstoodCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ResearchAggregatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ResearchAggregatesTable> {
  $$ResearchAggregatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get participantId => $composableBuilder(
    column: $table.participantId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get captureCount => $composableBuilder(
    column: $table.captureCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get handledCount => $composableBuilder(
    column: $table.handledCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get usefulReuseCount => $composableBuilder(
    column: $table.usefulReuseCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get accurateFeedbackCount => $composableBuilder(
    column: $table.accurateFeedbackCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get inaccurateFeedbackCount => $composableBuilder(
    column: $table.inaccurateFeedbackCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get understoodCount => $composableBuilder(
    column: $table.understoodCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get notUnderstoodCount => $composableBuilder(
    column: $table.notUnderstoodCount,
    builder: (column) => column,
  );
}

class $$ResearchAggregatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ResearchAggregatesTable,
          ResearchAggregateRow,
          $$ResearchAggregatesTableFilterComposer,
          $$ResearchAggregatesTableOrderingComposer,
          $$ResearchAggregatesTableAnnotationComposer,
          $$ResearchAggregatesTableCreateCompanionBuilder,
          $$ResearchAggregatesTableUpdateCompanionBuilder,
          (
            ResearchAggregateRow,
            BaseReferences<
              _$AppDatabase,
              $ResearchAggregatesTable,
              ResearchAggregateRow
            >,
          ),
          ResearchAggregateRow,
          PrefetchHooks Function()
        > {
  $$ResearchAggregatesTableTableManager(
    _$AppDatabase db,
    $ResearchAggregatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResearchAggregatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResearchAggregatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResearchAggregatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> participantId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> captureCount = const Value.absent(),
                Value<int> handledCount = const Value.absent(),
                Value<int> usefulReuseCount = const Value.absent(),
                Value<int> accurateFeedbackCount = const Value.absent(),
                Value<int> inaccurateFeedbackCount = const Value.absent(),
                Value<int> understoodCount = const Value.absent(),
                Value<int> notUnderstoodCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResearchAggregatesCompanion(
                participantId: participantId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                captureCount: captureCount,
                handledCount: handledCount,
                usefulReuseCount: usefulReuseCount,
                accurateFeedbackCount: accurateFeedbackCount,
                inaccurateFeedbackCount: inaccurateFeedbackCount,
                understoodCount: understoodCount,
                notUnderstoodCount: notUnderstoodCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String participantId,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> captureCount = const Value.absent(),
                Value<int> handledCount = const Value.absent(),
                Value<int> usefulReuseCount = const Value.absent(),
                Value<int> accurateFeedbackCount = const Value.absent(),
                Value<int> inaccurateFeedbackCount = const Value.absent(),
                Value<int> understoodCount = const Value.absent(),
                Value<int> notUnderstoodCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResearchAggregatesCompanion.insert(
                participantId: participantId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                captureCount: captureCount,
                handledCount: handledCount,
                usefulReuseCount: usefulReuseCount,
                accurateFeedbackCount: accurateFeedbackCount,
                inaccurateFeedbackCount: inaccurateFeedbackCount,
                understoodCount: understoodCount,
                notUnderstoodCount: notUnderstoodCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ResearchAggregatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ResearchAggregatesTable,
      ResearchAggregateRow,
      $$ResearchAggregatesTableFilterComposer,
      $$ResearchAggregatesTableOrderingComposer,
      $$ResearchAggregatesTableAnnotationComposer,
      $$ResearchAggregatesTableCreateCompanionBuilder,
      $$ResearchAggregatesTableUpdateCompanionBuilder,
      (
        ResearchAggregateRow,
        BaseReferences<
          _$AppDatabase,
          $ResearchAggregatesTable,
          ResearchAggregateRow
        >,
      ),
      ResearchAggregateRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$EvidenceBundlesTableTableManager get evidenceBundles =>
      $$EvidenceBundlesTableTableManager(_db, _db.evidenceBundles);
  $$SessionEventsTableTableManager get sessionEvents =>
      $$SessionEventsTableTableManager(_db, _db.sessionEvents);
  $$LocalRecordingsTableTableManager get localRecordings =>
      $$LocalRecordingsTableTableManager(_db, _db.localRecordings);
  $$ResearchCapturesTableTableManager get researchCaptures =>
      $$ResearchCapturesTableTableManager(_db, _db.researchCaptures);
  $$ResearchEventsTableTableManager get researchEvents =>
      $$ResearchEventsTableTableManager(_db, _db.researchEvents);
  $$ResearchAggregatesTableTableManager get researchAggregates =>
      $$ResearchAggregatesTableTableManager(_db, _db.researchAggregates);
}
