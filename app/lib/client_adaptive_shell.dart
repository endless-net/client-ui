import 'package:flutter/material.dart';

import 'client_locale.dart';
import 'client_session_panel.dart';

/// Navigation follows available logical space, including desktop split windows.
class ClientAdaptiveShell extends StatelessWidget {
  const ClientAdaptiveShell({
    super.key,
    required this.locale,
    required this.page,
    required this.onPageChanged,
    required this.languageSelector,
    required this.notices,
    required this.body,
  });

  final ClientLocale locale;
  final ClientPage page;
  final ValueChanged<ClientPage> onPageChanged;
  final Widget languageSelector;
  final Widget notices;
  final Widget body;

  String _label(ClientPage page) => switch (page) {
    ClientPage.connection => locale.text(en: 'Home', ru: 'Главная'),
    ClientPage.network => locale.text(en: 'Network', ru: 'Сеть'),
    ClientPage.settings => locale.text(en: 'Settings', ru: 'Настройки'),
    ClientPage.support => locale.text(en: 'Support', ru: 'Помощь'),
  };

  IconData _icon(ClientPage page) => switch (page) {
    ClientPage.connection => Icons.power_settings_new,
    ClientPage.network => Icons.hub_outlined,
    ClientPage.settings => Icons.tune,
    ClientPage.support => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rail = constraints.maxWidth >= 720 && constraints.maxHeight >= 400;
      final extended =
          constraints.maxWidth >= 1100 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20;
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 16,
          leadingWidth: 52,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Image.asset(
              'assets/icons/endlessnet.png',
              width: 32,
              height: 32,
            ),
          ),
          title: const Text(
            'EndlessNet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: languageSelector,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Row(
            children: [
              // Keep the content in the same tree slot when the window resizes.
              if (rail)
                NavigationRail(
                  extended: extended,
                  selectedIndex: page.index,
                  onDestinationSelected: (index) =>
                      onPageChanged(ClientPage.values[index]),
                  labelType: NavigationRailLabelType.none,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  destinations: [
                    for (final destination in ClientPage.values)
                      NavigationRailDestination(
                        icon: Tooltip(
                          message: _label(destination),
                          child: Icon(
                            _icon(destination),
                            key: ValueKey('page-${destination.name}'),
                          ),
                        ),
                        label: Text(_label(destination)),
                      ),
                  ],
                )
              else
                const SizedBox.shrink(),
              Expanded(
                child: Column(
                  children: [
                    Flexible(
                      flex: 0,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * .2,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: notices,
                        ),
                      ),
                    ),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: rail
            ? null
            : NavigationBar(
                selectedIndex: page.index,
                onDestinationSelected: (index) =>
                    onPageChanged(ClientPage.values[index]),
                labelBehavior:
                    NavigationDestinationLabelBehavior.onlyShowSelected,
                destinations: [
                  for (final destination in ClientPage.values)
                    NavigationDestination(
                      key: ValueKey('page-${destination.name}'),
                      icon: Icon(_icon(destination)),
                      label: _label(destination),
                    ),
                ],
              ),
      );
    },
  );
}
