enum ObservationVerdict {
  passed,
  failed,
  unverifiable;

  static ObservationVerdict fromRequiredFields(Map<String, bool> fields) {
    if (fields.isEmpty || fields.values.any((isAvailable) => !isAvailable)) {
      return ObservationVerdict.unverifiable;
    }
    return ObservationVerdict.passed;
  }
}
