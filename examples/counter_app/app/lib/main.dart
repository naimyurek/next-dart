import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:next_dart_rfw/next_dart_rfw.dart';
import 'keys.dart';

void main() {
  // For Android emulator use http://10.0.2.2:8080; for desktop/web/iOS-sim use localhost.
  // Demo: the client lives for the whole app lifetime and is intentionally not
  // closed. In a real app, own it in a StatefulWidget and close it in dispose().
  final client = NextDartClient(
    baseUrl: Uri.parse('http://localhost:8080'),
    signingPublicKey: SimplePublicKey(
        base64.decode(signingPublicKeyB64), type: KeyPairType.ed25519),
    secretKey: SecretKey(base64.decode(secretKeyB64)),
  );
  runApp(MyApp(client: client));
}

class MyApp extends StatelessWidget {
  final NextDartClient client;
  const MyApp({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'next-dart demo',
      home: Scaffold(
        appBar: AppBar(title: const Text('next-dart demo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: NextDartView(
            source: client,
            route: '/',
            renderer: RfwRenderer(),
          ),
        ),
      ),
    );
  }
}
