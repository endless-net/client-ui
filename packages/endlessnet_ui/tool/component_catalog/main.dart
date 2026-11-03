import 'package:endlessnet_ui/design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'cases.dart';

void main() => runApp(const ComponentCatalog());

class ComponentCatalog extends StatefulWidget {
  const ComponentCatalog({super.key});
  @override
  State<ComponentCatalog> createState() => _ComponentCatalogState();
}

class _ComponentCatalogState extends State<ComponentCatalog> {
  bool _dark = true, _reduced = false;
  var _definition = componentDefinitions.first;
  String? _variant, _state;
  String get _activeVariant => _variant ?? _definition.variants.first;
  List<String> get _states => _definition.statesFor(_activeVariant);
  String get _activeState => _state ?? _states.first;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EndlessNet — компоненты010',
    debugShowCheckedModeBanner: false,
    theme: _dark
        ? BrandTheme.dark(reducedMotion: _reduced)
        : BrandTheme.light(reducedMotion: _reduced),
    themeAnimationDuration: _reduced ? Duration.zero : BrandTokens.duration,
    home: Scaffold(
      appBar: AppBar(title: const Text('Компоненты010')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              title: const Text('Тёмная тема'),
              value: _dark,
              onChanged: (value) => setState(() => _dark = value),
            ),
            SwitchListTile(
              title: const Text('Уменьшить движение'),
              value: _reduced,
              onChanged: (value) => setState(() => _reduced = value),
            ),
            EnSelect(
              label: 'Компонент',
              value: _definition.id,
              options: {
                for (final value in componentDefinitions)
                  value.id: '${value.id} — ${value.title}',
              },
              onChanged: (value) => setState(() {
                _definition = componentDefinitions.firstWhere(
                  (item) => item.id == value,
                );
                _variant = null;
                _state = null;
              }),
            ),
            const SizedBox(height: 12),
            EnSelect(
              label: 'Вариант',
              value: _variant ?? _definition.variants.first,
              options: {for (final value in _definition.variants) value: value},
              onChanged: (value) => setState(() {
                _variant = value;
                _state = null;
              }),
            ),
            const SizedBox(height: 12),
            EnSelect(
              label: 'Состояние',
              value: _activeState,
              options: {for (final value in _states) value: value},
              onChanged: (value) => setState(() => _state = value),
            ),
            const SizedBox(height: 16),
            Text(_definition.contract),
            ExpansionTile(
              title: const Text('Неприменимые состояния (N/A)'),
              children: [
                for (final state
                    in componentDefinitions
                        .expand((item) => item.states)
                        .toSet())
                  if (_definition.notApplicable(state, variant: _activeVariant)
                      case final String reason)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(reason),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            ComponentExample(
              key: ValueKey('${_definition.id}/$_activeVariant/$_activeState'),
              id: _definition.id,
              variant: _variant ?? _definition.variants.first,
              state: _activeState,
            ),
          ],
        ),
      ),
    ),
  );
}
