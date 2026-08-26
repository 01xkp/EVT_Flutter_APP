import 'package:aipin/features/research_beta/domain/research_trial.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesResearchTrialStore implements ResearchTrialStore {
  static const _participantIdKey = 'research.participant_id';
  static const _startedAtKey = 'research.started_at';
  static const _consentedAtKey = 'research.consented_at';
  static const _lastPromptKey = 'research.last_understanding_prompt_on';

  @override
  Future<ResearchTrial?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final participantId = preferences.getString(_participantIdKey);
    final startedAt = _readDate(preferences.getString(_startedAtKey));
    if (participantId == null || startedAt == null) {
      return null;
    }
    return ResearchTrial(
      participantId: participantId,
      startedAt: startedAt,
      consentedAt: _readDate(preferences.getString(_consentedAtKey)),
      lastDailyUnderstandingPromptOn: _readDate(
        preferences.getString(_lastPromptKey),
      ),
    );
  }

  @override
  Future<void> save(ResearchTrial trial) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_participantIdKey, trial.participantId);
    await preferences.setString(
      _startedAtKey,
      trial.startedAt.toIso8601String(),
    );
    await _setDate(preferences, _consentedAtKey, trial.consentedAt);
    await _setDate(
      preferences,
      _lastPromptKey,
      trial.lastDailyUnderstandingPromptOn,
    );
  }

  DateTime? _readDate(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  Future<void> _setDate(
    SharedPreferences preferences,
    String key,
    DateTime? value,
  ) async {
    if (value == null) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, value.toIso8601String());
    }
  }
}
