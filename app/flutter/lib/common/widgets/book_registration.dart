import 'dart:convert';

import 'package:flutter/material.dart';
import '../../common.dart';
import '../../models/platform_model.dart';
import '../../utils/http_service.dart' as http;

class BookRegistration extends StatefulWidget {
  final Uri uri;
  final VoidCallback onBack;
  final VoidCallback onRegistered;

  const BookRegistration({
    super.key,
    required this.uri,
    required this.onBack,
    required this.onRegistered,
  });

  @override
  State<BookRegistration> createState() => _BookRegistrationState();
}

class _BookRegistrationState extends State<BookRegistration> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _name.text.trim();
    final password = _password.text;
    String? error;
    if (!RegExp(r'^[A-Za-z0-9._-]{3,40}$').hasMatch(name)) {
      error =
          'Usá de 3 a 40 letras sin acentos, números, puntos o guiones para el usuario.';
    } else if (password.runes.length < 12 || password.runes.length > 128) {
      error = 'La contraseña debe tener entre 12 y 128 caracteres.';
    } else if (password != _repeat.text) {
      error = 'Las contraseñas no coinciden.';
    }
    setState(() {
      _error = error;
      _busy = error == null;
    });
    if (error != null) return;
    try {
      final response = await http.post(widget.uri,
          body: jsonEncode({'username': name, 'password': password}));
      if (!mounted) return;
      if (response.statusCode == 201) {
        final data = jsonDecode(decode_http_response(response));
        if (data['type'] == 'access_token' &&
            data['access_token'] is String &&
            data['user']?['name'] == name) {
          final resp = gFFI.userModel.getLoginResponseFromAuthBody(data);
          await bind.mainSetLocalOption(
              key: 'user_info', value: jsonEncode(resp.user));
          await bind.mainSetLocalOption(
              key: 'access_token', value: resp.access_token!);
          if (mounted) widget.onRegistered();
          return;
        }
      } else if (response.statusCode == 409) {
        error =
            'Ese usuario ya existe. Volvé a iniciar sesión o elegí otro nombre.';
      } else if (response.statusCode == 429) {
        error =
            'Hubo varios intentos. Esperá un minuto antes de volver a probar.';
      }
      error ??=
          'No se pudo completar el registro (HTTP ${response.statusCode}).';
    } catch (_) {
      error =
          'No se pudo confirmar el registro. Revisá la conexión e intentá iniciar sesión.';
    } finally {
      if (mounted && error != null) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Usá esta cuenta en tus PC para sincronizar la libreta.'),
        TextField(
            controller: _name,
            autofocus: true,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Usuario')),
        TextField(
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(
                labelText: 'Contraseña', helperText: 'De 12 a 128 caracteres')),
        TextField(
            controller: _repeat,
            onSubmitted: (_) => _submit(),
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Repetir contraseña')),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
              onPressed: _busy ? null : widget.onBack,
              child: const Text('Volver')),
          ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Crear cuenta')),
        ]),
      ]);
}
