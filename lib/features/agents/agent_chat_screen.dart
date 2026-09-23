import 'package:flutter/material.dart';

class AgentChatScreen extends StatelessWidget {
  const AgentChatScreen({super.key, required this.agentId});

  final String agentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agent')),
      body: Center(child: Text(agentId)),
    );
  }
}
