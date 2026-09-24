import '../models/models.dart';

/// Initial fake state for [MockAgentBackend]. Timestamps are relative to [now]
/// so the data always looks fresh.
class MockSeed {
  MockSeed(this.now);

  final DateTime now;

  DateTime _ago({int days = 0, int hours = 0, int minutes = 0}) =>
      now.subtract(Duration(days: days, hours: hours, minutes: minutes));

  late final List<Project> projects = [
    Project(
      id: 'p1',
      name: 'ai_dashboard',
      path: r'C:\dev\ai_dashboard',
      branch: 'feat/agent-chat',
      lastActivity: _ago(minutes: 2),
      testRuns: [
        TestRun(
          id: 'r1',
          suite: 'flutter test',
          status: TestStatus.passed,
          passed: 24,
          failed: 0,
          duration: const Duration(seconds: 18),
          at: _ago(minutes: 12),
          agentId: 'a2',
        ),
        TestRun(
          id: 'r2',
          suite: 'flutter analyze',
          status: TestStatus.failed,
          passed: 0,
          failed: 2,
          failingTests: const [
            'lib/features/chat/chat_list.dart:42 unused_import',
            'lib/app/router.dart:17 prefer_const_constructors',
          ],
          duration: const Duration(seconds: 6),
          at: _ago(hours: 1),
          agentId: 'a2',
        ),
      ],
      log: [
        LogEntry(
          at: _ago(minutes: 2),
          agentId: 'a2',
          message: 'Codex edited lib/features/agents/chat_bubble.dart',
        ),
        LogEntry(
          at: _ago(minutes: 12),
          agentId: 'a2',
          level: LogLevel.success,
          message: 'flutter test: 24 passed',
        ),
        LogEntry(
          at: _ago(hours: 1),
          agentId: 'a2',
          level: LogLevel.warning,
          message: 'flutter analyze: 2 issues',
        ),
        LogEntry(
          at: _ago(hours: 2),
          agentId: 'a2',
          message: 'Checked out branch feat/agent-chat',
        ),
      ],
    ),
    Project(
      id: 'p2',
      name: 'shop-api',
      path: r'C:\dev\shop-api',
      branch: 'feature/payments',
      lastActivity: _ago(minutes: 1),
      testRuns: [
        TestRun(
          id: 'r3',
          suite: 'npm test -- payments',
          status: TestStatus.running,
          passed: 31,
          failed: 0,
          duration: const Duration(seconds: 40),
          at: _ago(minutes: 1),
          agentId: 'a1',
        ),
        TestRun(
          id: 'r4',
          suite: 'npm test',
          status: TestStatus.failed,
          passed: 118,
          failed: 3,
          failingTests: const [
            'checkout › applies discount codes',
            'checkout › rejects expired cards',
            'webhooks › verifies stripe signature',
          ],
          duration: const Duration(minutes: 1, seconds: 12),
          at: _ago(minutes: 35),
          agentId: 'a1',
        ),
        TestRun(
          id: 'r5',
          suite: 'npm test',
          status: TestStatus.passed,
          passed: 121,
          failed: 0,
          duration: const Duration(minutes: 1, seconds: 8),
          at: _ago(hours: 5),
          agentId: 'a1',
        ),
      ],
      log: [
        LogEntry(
          at: _ago(minutes: 1),
          agentId: 'a1',
          message: 'Claude #1 started npm test -- payments',
        ),
        LogEntry(
          at: _ago(minutes: 20),
          agentId: 'a3',
          message: 'Gemini is waiting for your review of the test plan',
        ),
        LogEntry(
          at: _ago(minutes: 35),
          agentId: 'a1',
          level: LogLevel.error,
          message: 'npm test: 3 failing',
        ),
        LogEntry(
          at: _ago(hours: 5),
          agentId: 'a1',
          level: LogLevel.success,
          message: 'Completed: Add rate limiting middleware',
        ),
      ],
    ),
    Project(
      id: 'p3',
      name: 'portfolio-site',
      path: r'C:\dev\portfolio-site',
      branch: 'main',
      lastActivity: _ago(hours: 1),
      testRuns: [
        TestRun(
          id: 'r6',
          suite: 'npm run build',
          status: TestStatus.passed,
          passed: 1,
          failed: 0,
          duration: const Duration(seconds: 22),
          at: _ago(hours: 1),
          agentId: 'a6',
        ),
      ],
      log: [
        LogEntry(
          at: _ago(hours: 1),
          agentId: 'a6',
          level: LogLevel.success,
          message: 'Completed: Migrate to Tailwind v4',
        ),
        LogEntry(
          at: _ago(hours: 3),
          agentId: 'a6',
          message: 'Codex #2 updated 14 components',
        ),
      ],
    ),
    Project(
      id: 'p4',
      name: 'ml-pipeline',
      path: r'C:\dev\ml-pipeline',
      branch: 'fix/flaky-tests',
      lastActivity: _ago(minutes: 20),
      testRuns: [
        TestRun(
          id: 'r7',
          suite: 'pytest',
          status: TestStatus.failed,
          passed: 57,
          failed: 3,
          failingTests: const [
            'tests/test_features.py::test_extract_dates',
            'tests/test_features.py::test_window_agg',
            'tests/test_store.py::test_cache_ttl',
          ],
          duration: const Duration(minutes: 2, seconds: 3),
          at: _ago(minutes: 20),
          agentId: 'a4',
        ),
      ],
      log: [
        LogEntry(
          at: _ago(minutes: 20),
          agentId: 'a4',
          level: LogLevel.error,
          message: 'Failed: Fix flaky feature extraction tests',
        ),
        LogEntry(
          at: _ago(minutes: 40),
          agentId: 'a4',
          message: 'Claude #2 checked out fix/flaky-tests',
        ),
      ],
    ),
  ];

  late final List<Agent> agents = [
    Agent(
      id: 'a1',
      name: 'Claude #1',
      type: AgentType.claudeCode,
      status: AgentStatus.running,
      activity: 'Handling checkout.session.completed events',
      lastActive: _ago(minutes: 1),
      projectId: 'p2',
      workingDir: r'C:\dev\shop-api',
      branch: 'feature/payments',
      currentTaskId: 't1',
    ),
    Agent(
      id: 'a2',
      name: 'Codex',
      type: AgentType.codex,
      status: AgentStatus.running,
      activity: 'Building message bubbles',
      lastActive: _ago(minutes: 2),
      projectId: 'p1',
      workingDir: r'C:\dev\ai_dashboard\lib\features',
      branch: 'feat/agent-chat',
      currentTaskId: 't2',
    ),
    Agent(
      id: 'a3',
      name: 'Gemini',
      type: AgentType.geminiCli,
      status: AgentStatus.waiting,
      activity: 'Waiting for approval of test plan',
      lastActive: _ago(minutes: 20),
      projectId: 'p2',
      workingDir: r'C:\dev\shop-api\test',
      branch: 'feature/payments',
    ),
    Agent(
      id: 'a4',
      name: 'Claude #2',
      type: AgentType.claudeCode,
      status: AgentStatus.failed,
      activity: '3 tests still failing after 4 attempts',
      lastActive: _ago(minutes: 20),
      projectId: 'p4',
      workingDir: r'C:\dev\ml-pipeline',
      branch: 'fix/flaky-tests',
    ),
    Agent(
      id: 'a5',
      name: 'Aider',
      type: AgentType.aider,
      status: AgentStatus.idle,
      activity: 'Idle',
      lastActive: _ago(days: 1, hours: 2),
    ),
    Agent(
      id: 'a6',
      name: 'Codex #2',
      type: AgentType.codex,
      status: AgentStatus.completed,
      activity: 'Finished: Migrate to Tailwind v4',
      lastActive: _ago(hours: 1),
      projectId: 'p3',
      workingDir: r'C:\dev\portfolio-site',
      branch: 'main',
    ),
  ];

  AgentTask _task(
    String id,
    String title,
    String projectId,
    TaskState state, {
    String? agentId,
    double progress = 0,
    List<String> steps = const [],
    required DateTime created,
    DateTime? completed,
  }) {
    final doneSteps = (progress * steps.length).floor();
    return AgentTask(
      id: id,
      title: title,
      projectId: projectId,
      agentId: agentId,
      state: state,
      progress: progress,
      steps: [
        for (var i = 0; i < steps.length; i++)
          TaskStep(steps[i], done: i < doneSteps),
      ],
      createdAt: created,
      updatedAt: completed ?? created,
      completedAt: completed,
    );
  }

  late final List<AgentTask> tasks = [
    _task(
      't1',
      'Implement Stripe webhook handler',
      'p2',
      TaskState.active,
      agentId: 'a1',
      progress: 0.55,
      steps: const [
        'Read existing payment module',
        'Add /webhooks/stripe route',
        'Verify event signatures',
        'Handle checkout.session.completed events',
        'Write integration tests',
        'Update API docs',
      ],
      created: _ago(hours: 2),
    ),
    _task(
      't2',
      'Build agent chat screen',
      'p1',
      TaskState.active,
      agentId: 'a2',
      progress: 0.3,
      steps: const [
        'Scaffold screen and route',
        'Building message bubbles',
        'Add composer with quick prompts',
        'Wire to chat provider',
        'Widget tests',
      ],
      created: _ago(hours: 1, minutes: 30),
    ),
    _task(
      't3',
      'Write tests for checkout flow',
      'p2',
      TaskState.waiting,
      agentId: 'a3',
      created: _ago(hours: 1),
    ),
    _task(
      't4',
      'Refactor order service',
      'p2',
      TaskState.waiting,
      agentId: 'a1',
      created: _ago(minutes: 50),
    ),
    _task(
      't5',
      'Add push notifications',
      'p1',
      TaskState.backlog,
      created: _ago(days: 1),
    ),
    _task(
      't6',
      'Dark mode for blog pages',
      'p3',
      TaskState.backlog,
      created: _ago(days: 2),
    ),
    _task(
      't7',
      'Cache feature store lookups',
      'p4',
      TaskState.backlog,
      created: _ago(days: 3),
    ),
    _task(
      't8',
      'Migrate to Tailwind v4',
      'p3',
      TaskState.completed,
      agentId: 'a6',
      progress: 1,
      created: _ago(hours: 4),
      completed: _ago(hours: 1),
    ),
    _task(
      't9',
      'Add rate limiting middleware',
      'p2',
      TaskState.completed,
      agentId: 'a1',
      progress: 1,
      created: _ago(hours: 8),
      completed: _ago(hours: 5),
    ),
    _task(
      't10',
      'Fix flaky feature extraction tests',
      'p4',
      TaskState.failed,
      agentId: 'a4',
      progress: 0.8,
      created: _ago(hours: 1),
      completed: _ago(minutes: 20),
    ),
    _task(
      't11',
      'Set up project scaffolding',
      'p1',
      TaskState.completed,
      agentId: 'a2',
      progress: 1,
      created: _ago(days: 1, hours: 4),
      completed: _ago(days: 1, hours: 2),
    ),
    _task(
      't12',
      'Add SEO meta tags',
      'p3',
      TaskState.completed,
      agentId: 'a3',
      progress: 1,
      created: _ago(days: 3, hours: 2),
      completed: _ago(days: 3),
    ),
    _task(
      't13',
      'Dockerize API',
      'p2',
      TaskState.completed,
      agentId: 'a1',
      progress: 1,
      created: _ago(days: 5, hours: 3),
      completed: _ago(days: 5),
    ),
    _task(
      't14',
      'Train/test split script',
      'p4',
      TaskState.completed,
      agentId: 'a4',
      progress: 1,
      created: _ago(days: 2, hours: 5),
      completed: _ago(days: 2),
    ),
  ];

  ChatMessage _msg(
    String id,
    String agentId,
    MessageRole role,
    String text,
    DateTime at,
  ) => ChatMessage(id: id, agentId: agentId, role: role, text: text, at: at);

  late final Map<String, List<ChatMessage>> messages = {
    'a1': [
      _msg(
        'm1',
        'a1',
        MessageRole.system,
        r'Assigned to C:\dev\shop-api',
        _ago(hours: 2),
      ),
      _msg(
        'm2',
        'a1',
        MessageRole.user,
        'Implement the Stripe webhook handler. Verify signatures and handle checkout completion.',
        _ago(hours: 2),
      ),
      _msg(
        'm3',
        'a1',
        MessageRole.agent,
        "On it. I'll add a /webhooks/stripe route, verify signatures with the signing secret from .env, and handle checkout.session.completed.",
        _ago(hours: 2),
      ),
      _msg(
        'm4',
        'a1',
        MessageRole.agent,
        '**Route and signature verification are in.**\n\n'
            '- Added `POST /webhooks/stripe` in `src/routes/webhooks.ts`\n'
            '- Signatures are checked with `STRIPE_WEBHOOK_SECRET` from `.env`\n'
            '- `checkout.session.completed` marks the order as paid\n\n'
            '3 existing checkout tests are failing — looks unrelated '
            '(expired fixture card). Fixing those next.',
        _ago(minutes: 35),
      ),
    ],
    'a2': [
      _msg(
        'm5',
        'a2',
        MessageRole.system,
        r'Assigned to C:\dev\ai_dashboard\lib\features',
        _ago(hours: 1, minutes: 30),
      ),
      _msg(
        'm6',
        'a2',
        MessageRole.user,
        'Build the agent chat screen with bubbles and a composer.',
        _ago(hours: 1, minutes: 30),
      ),
      _msg(
        'm7',
        'a2',
        MessageRole.agent,
        'Scaffolded the screen and route. Working on message bubbles now.',
        _ago(minutes: 2),
      ),
    ],
    'a3': [
      _msg(
        'm8',
        'a3',
        MessageRole.agent,
        'I drafted a test plan for the checkout flow: 12 cases covering discounts, taxes and card failures. Should I proceed?',
        _ago(minutes: 20),
      ),
    ],
    'a4': [
      _msg(
        'm9',
        'a4',
        MessageRole.user,
        'Fix the flaky feature extraction tests.',
        _ago(hours: 1),
      ),
      _msg(
        'm10',
        'a4',
        MessageRole.agent,
        'After 4 attempts, 3 tests still fail. `test_extract_dates` '
            'depends on the local timezone:\n\n'
            '```python\n'
            'assert extract_dates(row)[0] == date(2024, 3, 10)  # fails outside UTC\n'
            '```\n\n'
            '| Option | Change | Risk |\n'
            '|---|---|---|\n'
            '| Pin TZ | `TZ=UTC` in CI | Hides real bugs |\n'
            '| Rewrite fixture | Use aware datetimes | Bigger diff |\n\n'
            'I need guidance: **pin TZ in CI** or **rewrite the fixture**?',
        _ago(minutes: 20),
      ),
    ],
  };

  /// Local midnight [days] from today (negative for the past).
  DateTime _day(int days) =>
      DateTime(now.year, now.month, now.day).add(Duration(days: days));

  late final List<TodoList> todoLists = [
    TodoList(
      id: 'l1',
      title: 'v1.2 release',
      createdAt: _ago(days: 6),
      updatedAt: _ago(hours: 3),
      items: [
        TodoItem(
          id: 'i1',
          title: 'Stripe webhooks live in production',
          note: 'Check signature secrets are set on the prod host first.',
          projectIds: const ['p2'],
          agentIds: const ['a1'],
          startDate: _day(-3),
          dueDate: _day(2),
          createdAt: _ago(days: 6),
        ),
        TodoItem(
          id: 'i2',
          title: 'Polish agent chat bubbles',
          projectIds: const ['p1'],
          agentIds: const ['a2'],
          dueDate: _day(5),
          createdAt: _ago(days: 5),
        ),
        TodoItem(
          id: 'i3',
          title: 'Get the flaky ML tests green',
          projectIds: const ['p4'],
          agentIds: const ['a4', 'a5'],
          dueDate: _day(-1),
          createdAt: _ago(days: 4),
        ),
        TodoItem(
          id: 'i4',
          title: 'Write release notes',
          dueDate: _day(7),
          createdAt: _ago(days: 3),
        ),
        TodoItem(
          id: 'i5',
          title: 'Rotate staging database credentials',
          projectIds: const ['p2'],
          done: true,
          createdAt: _ago(days: 6),
          completedAt: _ago(days: 1),
        ),
      ],
    ),
    TodoList(
      id: 'l2',
      title: 'Someday ideas',
      createdAt: _ago(days: 12),
      updatedAt: _ago(days: 2),
      items: [
        TodoItem(
          id: 'i6',
          title: 'Try Gemini for generating API test cases',
          projectIds: const ['p2'],
          agentIds: const ['a3'],
          createdAt: _ago(days: 12),
        ),
        TodoItem(
          id: 'i7',
          title: 'Dark-mode screenshots for the portfolio',
          projectIds: const ['p3'],
          createdAt: _ago(days: 9),
        ),
      ],
    ),
  ];
}
