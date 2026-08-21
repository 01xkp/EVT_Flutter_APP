import 'package:evt_ble_app/features/evidence/domain/evidence_bundle.dart';
import 'package:evt_ble_app/features/evidence/domain/evidence_repository.dart';

class FakeEvidenceRepository implements EvidenceRepository {
  FakeEvidenceRepository([List<EvidenceBundle> values = const []])
    : values = [...values];

  final List<EvidenceBundle> values;

  @override
  Future<List<EvidenceBundle>> all() async => List.unmodifiable(values);

  @override
  Future<EvidenceBundle?> byId(String id) async {
    for (final value in values) {
      if (value.id == id) {
        return value;
      }
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    values.removeWhere((value) => value.id == id);
  }

  @override
  Future<void> save(EvidenceBundle bundle) async {
    values.add(bundle);
  }
}
