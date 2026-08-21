import 'package:evt_ble_app/features/evidence/domain/evidence_bundle.dart';

abstract interface class EvidenceRepository {
  Future<void> save(EvidenceBundle bundle);
  Future<EvidenceBundle?> byId(String id);
  Future<List<EvidenceBundle>> all();
  Future<void> delete(String id);
}
