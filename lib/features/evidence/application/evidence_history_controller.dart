import 'package:aipin/features/evidence/domain/evidence_bundle.dart';
import 'package:aipin/features/evidence/domain/evidence_repository.dart';
import 'package:flutter/foundation.dart';

class EvidenceHistoryState {
  const EvidenceHistoryState({
    this.items = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<EvidenceBundle> items;
  final bool isLoading;
  final String? errorMessage;
}

class EvidenceHistoryController extends ChangeNotifier {
  EvidenceHistoryController(this._repository);

  final EvidenceRepository _repository;
  EvidenceHistoryState _state = const EvidenceHistoryState();

  EvidenceHistoryState get state => _state;

  Future<void> load() async {
    _state = EvidenceHistoryState(items: _state.items, isLoading: true);
    notifyListeners();
    try {
      final items = await _repository.all();
      _state = EvidenceHistoryState(items: List.unmodifiable(items));
    } catch (_) {
      _state = EvidenceHistoryState(
        items: _state.items,
        errorMessage: '证据记录暂时不可读取。',
      );
    }
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }
}
