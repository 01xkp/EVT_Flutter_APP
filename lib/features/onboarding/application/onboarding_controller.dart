import 'package:evt_ble_app/features/onboarding/domain/onboarding_store.dart';
import 'package:flutter/foundation.dart';

class OnboardingController extends ChangeNotifier {
  OnboardingController(this._store);

  final OnboardingStore _store;
  bool _isComplete = false;

  bool get isComplete => _isComplete;

  Future<bool> load() async {
    _isComplete = await _store.isComplete();
    notifyListeners();
    return _isComplete;
  }

  Future<void> complete() async {
    await _store.markComplete();
    _isComplete = true;
    notifyListeners();
  }
}
