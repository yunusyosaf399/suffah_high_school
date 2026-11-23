class FinanceAutomationPreference {
  const FinanceAutomationPreference({
    required this.category,
    required this.scheduleDay,
    required this.automaticEnabled,
  });

  final String category;
  final int scheduleDay;
  final bool automaticEnabled;

  FinanceAutomationPreference copyWith({
    int? scheduleDay,
    bool? automaticEnabled,
  }) => FinanceAutomationPreference(
    category: category,
    scheduleDay: scheduleDay ?? this.scheduleDay,
    automaticEnabled: automaticEnabled ?? this.automaticEnabled,
  );
}

class FinanceAutomationPlan {
  const FinanceAutomationPlan({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.scheduleDay,
    required this.active,
    required this.automaticEnabled,
  });

  final String id;
  final String name;
  final int amountMinor;
  final int scheduleDay;
  final bool active;
  final bool automaticEnabled;

  FinanceAutomationPlan copyWith({
    int? scheduleDay,
    bool? automaticEnabled,
  }) => FinanceAutomationPlan(
    id: id,
    name: name,
    amountMinor: amountMinor,
    scheduleDay: scheduleDay ?? this.scheduleDay,
    active: active,
    automaticEnabled: automaticEnabled ?? this.automaticEnabled,
  );
}

class FinanceAutomationSnapshot {
  const FinanceAutomationSnapshot({
    required this.preferences,
    required this.plans,
    this.lastHeartbeat,
    this.lastCompleted,
  });

  final Map<String, FinanceAutomationPreference> preferences;
  final List<FinanceAutomationPlan> plans;
  final DateTime? lastHeartbeat;
  final DateTime? lastCompleted;

  /// A stale worker heartbeat is not evidence that the scheduler is online.
  bool workerConnected(DateTime now) {
    final last = lastHeartbeat;
    if (last == null) return false;
    final difference = now.difference(last);
    return difference >= Duration.zero &&
        difference < const Duration(hours: 48);
  }
}

const financeSchedulerCategories = <String, String>{
  'tuition': 'Tuition fees',
  'transport': 'Transport fees',
  'salary': 'Teacher salaries',
};
