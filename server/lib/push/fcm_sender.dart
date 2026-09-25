import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'push_notifier.dart';

/// Sends notifications through Firebase Cloud Messaging (HTTP v1), signed in
/// with a Firebase service-account key.
///
/// The OAuth client is created on the first send, so a PC that starts up
/// offline still comes up, and is created again after a failed sign-in.
class FcmSender implements PushSender {
  FcmSender(this._credentials, {required this.projectId});

  /// Reads a service-account key downloaded from the Firebase console.
  factory FcmSender.fromFile(String path) {
    final Json json;
    try {
      json = jsonDecode(File(path).readAsStringSync()) as Json;
    } on Object catch (e) {
      throw FormatException("Can't read the Firebase key at $path: $e");
    }
    final projectId = json['project_id'];
    if (json['type'] != 'service_account' || projectId is! String) {
      throw FormatException('$path is not a Firebase service-account key');
    }
    return FcmSender(
      ServiceAccountCredentials.fromJson(json),
      projectId: projectId,
    );
  }

  /// Must match the channel `MainActivity` creates.
  static const channelId = 'agent_updates';
  static const _scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

  final ServiceAccountCredentials _credentials;
  final String projectId;
  Future<AutoRefreshingAuthClient>? _client;

  Uri get _endpoint =>
      Uri.https('fcm.googleapis.com', '/v1/projects/$projectId/messages:send');

  @override
  Future<bool> send(String token, PushMessage message) async {
    final http.Response response;
    try {
      final client = await (_client ??= clientViaServiceAccount(
        _credentials,
        _scopes,
      ));
      response = await client.post(
        _endpoint,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'message': {
            'token': token,
            'notification': {'title': message.title, 'body': message.body},
            'data': message.data,
            'android': {
              'priority': 'HIGH',
              'notification': {'channel_id': channelId, 'tag': ?message.tag},
            },
          },
        }),
      );
    } on Object catch (e) {
      _client = null;
      throw PushException("Can't reach FCM: $e");
    }
    if (response.statusCode == 200) return true;
    if (response.statusCode == 404 || response.body.contains('UNREGISTERED')) {
      return false;
    }
    throw PushException(
      'FCM answered ${response.statusCode}: ${_errorOf(response.body)}',
    );
  }

  static String _errorOf(String body) {
    try {
      final error = (jsonDecode(body) as Json)['error'] as Json;
      return error['message'] as String;
    } on Object {
      return body;
    }
  }

  @override
  void close() {
    _client?.then((c) => c.close()).ignore();
    _client = null;
  }
}
