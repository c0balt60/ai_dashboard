/// Everything shared by the Flutter app and the PC server: models, the
/// [AgentBackend] contract, the in-memory mock and the wire protocol.
library;

export 'models.dart';
export 'src/models/json.dart' show decodeDayOrNull, decodeStrings, encodeDay;
export 'src/backend/agent_backend.dart';
export 'src/backend/mock_backend.dart';
export 'src/protocol.dart';
