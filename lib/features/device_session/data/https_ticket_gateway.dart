import 'dart:convert';
import 'dart:io';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/data/https_device_service_support.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';

class HttpsTicketGateway implements TicketGateway {
  HttpsTicketGateway({
    required String baseUrl,
    this.allowInsecureHttpForTesting = false,
    HttpClient Function()? clientFactory,
    SafeAppLogger? logger,
  }) : _endpoint = DeviceServiceEndpoint(
         baseUrl: baseUrl,
         allowInsecureHttpForTesting: allowInsecureHttpForTesting,
       ),
       _clientFactory = clientFactory ?? HttpClient.new,
       _logger = logger ?? const DebugSafeAppLogger(scope: 'DEVICE_API');

  final bool allowInsecureHttpForTesting;
  final DeviceServiceEndpoint _endpoint;
  final HttpClient Function() _clientFactory;
  final SafeAppLogger _logger;

  @override
  Future<TicketMaterial> issue(TicketRequest request) async {
    final client = _clientFactory();
    configureDeviceServiceClient(client);
    try {
      final payload = <String, Object?>{
        'device_id': request.deviceId,
        'action': request.action.wireValue,
        'transaction_id': request.transactionId,
        'device_payload_base64': base64Encode(request.devicePayload),
      };
      _logger.info(
        'ticket_issue_started',
        fields: {'action': request.action.name},
      );
      final httpRequest = await withDeviceServiceTimeout(
        client.postUrl(_endpoint.path('/v1/device-tickets')),
        stage: '认证票据连接',
      );
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.add(utf8.encode(jsonEncode(payload)));
      final response = await withDeviceServiceTimeout(
        httpRequest.close(),
        stage: '认证票据请求',
      );
      final body = await withDeviceServiceTimeout(
        decodeDeviceServiceJson(response),
        stage: '认证票据响应',
      );
      final ticket = _decodeBase64(
        body['ticket_base64'],
        field: 'ticket_base64',
      );
      final proofKey = _decodeBase64(
        body['proof_key_base64'],
        field: 'proof_key_base64',
      );
      if (ticket.isEmpty || proofKey.length != 32) {
        throw const DeviceServiceHttpException('认证服务返回的票据或证明密钥无效。');
      }
      _logger.info(
        'ticket_issue_succeeded',
        fields: {'action': request.action.name, 'ticket_bytes': ticket.length},
      );
      return TicketMaterial(ticket: ticket, proofKey: proofKey);
    } finally {
      client.close(force: true);
    }
  }

  static List<int> _decodeBase64(Object? value, {required String field}) {
    if (value is! String || value.trim().isEmpty) {
      throw DeviceServiceHttpException('认证服务缺少 $field。');
    }
    try {
      return base64Decode(value);
    } on FormatException {
      throw DeviceServiceHttpException('认证服务的 $field 不是 Base64。');
    }
  }
}
