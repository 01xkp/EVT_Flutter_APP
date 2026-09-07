import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aipin/features/device_session/data/https_archive_gateway.dart';
import 'package:aipin/features/device_session/data/https_firmware_package_gateway.dart';
import 'package:aipin/features/device_session/data/https_ticket_gateway.dart';
import 'package:aipin/features/device_session/domain/archive_gateway.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ticket gateway sends the V1.5 action envelope and validates proof key',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/device-tickets');
        final body = jsonDecode(await utf8.decodeStream(request));
        expect(body, {
          'device_id': 'device-1',
          'action': 0x20,
          'transaction_id': 42,
          'device_payload_base64': 'AQI=',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'ticket_base64': 'qrs=',
            'proof_key_base64': base64Encode(List<int>.filled(32, 7)),
          }),
        );
        await request.response.close();
      });
      final gateway = HttpsTicketGateway(
        baseUrl: _baseUrl(server),
        allowInsecureHttpForTesting: true,
      );

      final material = await gateway.issue(
        const TicketRequest(
          deviceId: 'device-1',
          action: DeviceAuthAction.authenticate,
          transactionId: 42,
          devicePayload: [1, 2],
        ),
      );

      expect(material.ticket, Uint8List.fromList(const [0xAA, 0xBB]));
      expect(material.proofKey, hasLength(32));
    },
  );

  test('archive gateway waits for a durable archive receipt', () async {
    final sourceDirectory = await Directory.systemTemp.createTemp(
      'aipin_archive_',
    );
    addTearDown(() => sourceDirectory.delete(recursive: true));
    final source = File(
      '${sourceDirectory.path}${Platform.pathSeparator}capture.ogg',
    );
    await source.writeAsBytes(const [1, 2, 3]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/device-archives');
      final body = latin1.decode(
        await request.fold<List<int>>(
          <int>[],
          (bytes, value) => bytes..addAll(value),
        ),
      );
      expect(body, contains('name="device_id"'));
      expect(body, contains('device-1'));
      expect(body, contains('name="file_name_slot_base64"'));
      expect(body, contains(base64Encode(const [0x61, 0x62, 0x00])));
      expect(body, contains('name="audio"; filename="capture.ogg"'));
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"durable":true,"archive_id":"archive-1"}');
      await request.response.close();
    });
    final gateway = HttpsArchiveGateway(
      baseUrl: _baseUrl(server),
      allowInsecureHttpForTesting: true,
    );

    await gateway.archive(
      DeviceArchiveRequest(
        deviceId: 'device-1',
        absolutePath: source.path,
        sizeBytes: 3,
        crc32: 0x55BC801D,
        metadata: DeviceFileMetadata(
          name: 'ab',
          nameSlot: const [0x61, 0x62, 0x00],
          startUtc: DateTime.utc(2026, 9, 2),
          durationSeconds: 1,
          recordingSessionId: 1,
          segmentIndex: 0,
          clockQuality: 1,
          utcCorrectionMilliseconds: 0,
          length: 3,
          crc32: 0x55BC801D,
          state: 1,
        ),
      ),
    );
  });

  test(
    'firmware gateway loads a manifest and its declared HTTPS payload',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        if (request.uri.path == '/payload.bin') {
          request.response.add(const [1, 2, 3]);
          await request.response.close();
          return;
        }
        expect(request.method, 'GET');
        expect(request.uri.path, '/v1/firmware-packages');
        expect(request.uri.queryParameters['device_id'], 'device-1');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'vendor_id': 0x1234,
            'product_id': 0x5678,
            'image_version': 2,
            'expected_business_version': '1.0.2',
            'payload_crc32': 0x55BC801D,
            'wqota_request_prefix_flags': [0x70, 0x07, 0x6E, 0xC1],
            'wqota_response_prefix_flags': [0x70, 0x07, 0x6E, 0x01],
            'wqota_final_verification_supported': true,
            'payload_url': '${_baseUrl(server)}/payload.bin',
          }),
        );
        await request.response.close();
      });
      final gateway = HttpsFirmwarePackageGateway(
        baseUrl: _baseUrl(server),
        allowInsecureHttpForTesting: true,
      );

      final package = await gateway.loadForDevice('device-1');

      expect(package.vendorId, 0x1234);
      expect(package.productId, 0x5678);
      expect(package.payload, Uint8List.fromList(const [1, 2, 3]));
      expect(package.wqotaFinalVerificationSupported, isTrue);
    },
  );
}

String _baseUrl(HttpServer server) =>
    'http://${server.address.address}:${server.port}';
