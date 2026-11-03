import 'package:endlessnet_ui/design_system/design_system.dart';
import 'package:flutter/material.dart';

@immutable
class ComponentDefinition {
  const ComponentDefinition(
    this.id,
    this.title,
    this.variants,
    this.states,
    this.contract,
  );
  final String id, title, contract;
  final List<String> variants, states;
  List<String> statesFor(String variant) {
    if (id == 'C04' && ['checkbox', 'switch'].contains(variant)) {
      return states
          .where((state) => state != 'empty' && state != 'unknown')
          .toList();
    }
    if (id == 'C18' && variant == 'details') {
      return states.where((state) => state != 'collapsed').toList();
    }
    if (id == 'C20' && variant != 'copy') {
      return states.where((state) => state != 'error').toList();
    }
    if (id == 'C15' && variant == 'tooltip') return ['default', 'focus'];
    return states;
  }

  // N/A is explicit, rather than pretending every component has all states.
  String? notApplicable(String state, {String? variant}) =>
      (variant == null ? states : statesFor(variant)).contains(state)
      ? null
      : 'N/A: $state не является состоянием $id; состояние данных/операции задаёт owner.';
}

const componentDefinitions = [
  ComponentDefinition(
    'C01',
    'Основы',
    ['palette', 'typography', 'logo', 'mark', 'spacing', 'motion'],
    ['default'],
    'Тема/reduced motion → только представление; локальные assets.',
  ),
  ComponentDefinition(
    'C02',
    'Кнопки',
    ['primary', 'secondary', 'text', 'danger', 'icon', 'group'],
    ['default', 'hover', 'focus', 'pressed', 'disabled', 'pending'],
    'label/kind/enabled/pending → один callback; disabledReason.',
  ),
  ComponentDefinition(
    'C03',
    'Поля',
    [
      'text',
      'multiline',
      'number',
      'password',
      'read-only',
      'prefix-suffix',
      'helper',
    ],
    ['default', 'hover', 'focus', 'disabled', 'error', 'pending'],
    'controller/error → onChanged/onSubmit; draft остаётся у owner.',
  ),
  ComponentDefinition(
    'C04',
    'Выбор',
    ['select', 'checkbox', 'radio', 'switch', 'segmented'],
    ['default', 'focus', 'disabled', 'selected', 'empty', 'unknown'],
    'value/options/enabled → onChanged; без неявного выбора.',
  ),
  ComponentDefinition(
    'C05',
    'Форма',
    ['group'],
    ['default', 'error', 'disabled', 'pending'],
    'owner errors/canSubmit → onSubmit, без бизнес-валидации.',
  ),
  ComponentDefinition(
    'C06',
    'Поиск',
    ['search', 'filters'],
    ['default', 'disabled', 'empty'],
    'query/filters → onChanged/onClear; без запросов/debounce.',
  ),
  ComponentDefinition(
    'C07',
    'Таблица',
    ['table'],
    ['default', 'empty', 'selected', 'disabled'],
    'keyed rows/selection/sort → intents; без загрузки/пересортировки.',
  ),
  ComponentDefinition(
    'C08',
    'Список',
    ['list'],
    ['default', 'empty', 'selected', 'disabled'],
    'keyed items → onActivate; права задаёт owner.',
  ),
  ComponentDefinition(
    'C09',
    'Навигация набора',
    ['pager'],
    ['default', 'pending', 'empty', 'unknown', 'disabled'],
    'loaded/total?/hasNext → callbacks; unknown total != 0.',
  ),
  ComponentDefinition(
    'C10',
    'Карточка и секция',
    ['card', 'section', 'toolbar'],
    ['default', 'empty'],
    'title/description/content/actions slots; без операций.',
  ),
  ComponentDefinition(
    'C11',
    'Статус',
    ['badge'],
    [
      'default',
      'success',
      'warning',
      'error',
      'pending',
      'unknown',
      'unavailable',
    ],
    'label/kind/reason, смысл текстом и semantics.',
  ),
  ComponentDefinition(
    'C12',
    'Сообщение',
    ['inline', 'banner', 'snackbar'],
    ['default', 'success', 'warning', 'error'],
    'message/action/dismiss; закрыть сообщение не значит отменить операцию.',
  ),
  ComponentDefinition(
    'C13',
    'Область',
    ['region'],
    ['loading', 'empty', 'error', 'unknown', 'unavailable'],
    'явное состояние/причина; retry только по действию.',
  ),
  ComponentDefinition(
    'C14',
    'Подтверждение',
    ['normal', 'danger'],
    ['default', 'pending', 'error'],
    'onConfirm/onError; focus Cancel; pending не dismiss.',
  ),
  ComponentDefinition(
    'C15',
    'Меню и tooltip',
    ['menu', 'tooltip'],
    ['default', 'disabled', 'empty'],
    'items/enabled/reason → onSelected.',
  ),
  ComponentDefinition(
    'C16',
    'Вкладки',
    ['tabs'],
    ['default', 'disabled', 'unknown'],
    'items/selected → onSelect; draft owner не сбрасывается.',
  ),
  ComponentDefinition(
    'C17',
    'Каркас',
    ['shell'],
    ['default'],
    'header/body/navigation slots, drawer<840/sidebar≥840; без страниц.',
  ),
  ComponentDefinition(
    'C18',
    'Подробности',
    ['details', 'disclosure'],
    ['default', 'empty', 'unknown', 'collapsed'],
    'values/expanded → onExpand; missing != empty.',
  ),
  ComponentDefinition(
    'C19',
    'Прогресс',
    ['progress'],
    ['default', 'pending', 'unknown', 'completed'],
    'fraction либо indeterminate; completed только от owner.',
  ),
  ComponentDefinition(
    'C20',
    'Машинное значение',
    ['selectable', 'plain', 'sensitive', 'copy'],
    ['default', 'empty', 'error'],
    'text/sensitive/copy callback; ошибка clipboard != success.',
  ),
];

/// One synthetic owner; catalog and component tests use the production widgets.
class ComponentExample extends StatefulWidget {
  const ComponentExample({
    super.key,
    required this.id,
    required this.variant,
    required this.state,
    this.longText = false,
  });
  final String id, variant, state;
  final bool longText;
  @override
  State<ComponentExample> createState() => _ComponentExampleState();
}

class _ComponentExampleState extends State<ComponentExample> {
  final _draft = TextEditingController(text: 'Демонстрационные данные');
  String? _choice = 'one';
  bool _checked = false;
  bool _expanded = true;
  int _calls = 0;
  String? _error;
  final _selected = <String>{};
  @override
  void initState() {
    super.initState();
    if (widget.state == 'empty') _draft.clear();
    if (widget.state == 'unknown') _choice = 'missing';
    _checked = widget.state == 'selected';
    _expanded = widget.state != 'collapsed';
    if (widget.state == 'selected') {
      _selected.add('demo');
      if (widget.id == 'C08') _choice = 'demo';
    }
  }

  void _called() => setState(() => _calls++);
  String get label => widget.longText
      ? 'Очень длинное демонстрационное название элемента для проверки переноса текста без потери смысла'
      : 'Действие';
  bool get disabled => widget.state == 'disabled';
  bool get pending => widget.state == 'pending';
  bool get empty => widget.state == 'empty';
  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final variant = widget.variant;
    final state = widget.state;
    Widget example;
    switch (widget.id) {
      case 'C01':
        example = switch (variant) {
          'logo' => const BrandLogo(),
          'mark' => const Wrap(
            spacing: 16,
            children: [BrandMark(size: 16), BrandMark(size: 32), BrandMark()],
          ),
          'typography' => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Заголовок',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              Text(
                'Название',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                'Подзаголовок',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Крупный текст',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              Text(
                'Обычный текст',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text('Подпись', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          'spacing' => Wrap(
            spacing: 8,
            children: [
              for (final value in BrandTokens.spacing)
                SizedBox(width: value + 32, child: Text('$value px')),
            ],
          ),
          'motion' => Text(
            'Переход: ${BrandColors.of(context).motion.inMilliseconds} ms',
          ),
          _ => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in [
                BrandTokens.cyan,
                BrandTokens.blue,
                BrandTokens.indigo,
              ])
                SizedBox(
                  width: 64,
                  height: 44,
                  child: ColoredBox(color: color),
                ),
            ],
          ),
        };
      case 'C02':
        final kind = EnButtonKind.values.firstWhere(
          (value) => value.name == variant,
          orElse: () => EnButtonKind.primary,
        );
        example = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            EnButton(
              label: label,
              icon: Icons.add,
              kind: kind,
              enabled: !disabled,
              autofocus: state == 'focus',
              pending: pending,
              disabledReason: 'Действие недоступно',
              onPressed: _called,
            ),
            if (variant == 'group')
              EnButton(
                label: 'Отмена',
                kind: EnButtonKind.secondary,
                onPressed: _called,
              ),
          ],
        );
      case 'C03':
        example = EnField(
          label: widget.longText ? label : 'Поле',
          controller: _draft,
          helper: pending
              ? 'Ожидание'
              : variant == 'helper'
              ? 'Подсказка'
              : null,
          error: state == 'error' ? 'Проверьте значение' : null,
          enabled: !disabled,
          secret: variant == 'password',
          readOnly: variant == 'read-only' || pending,
          maxLines: variant == 'multiline' ? 3 : 1,
          keyboardType: variant == 'number' ? TextInputType.number : null,
          prefix: variant == 'prefix-suffix' ? const Icon(Icons.link) : null,
          suffix: variant == 'prefix-suffix'
              ? const Icon(Icons.info_outline)
              : null,
        );
      case 'C04':
        final choice = _choice;
        example = switch (variant) {
          'checkbox' => CheckboxListTile(
            title: Text(label),
            value: _checked,
            onChanged: disabled
                ? null
                : (value) => setState(() => _checked = value ?? false),
          ),
          'switch' => SwitchListTile(
            title: Text(label),
            value: _checked,
            onChanged: disabled
                ? null
                : (value) => setState(() => _checked = value),
          ),
          'radio' => RadioGroup<String>(
            groupValue: choice,
            onChanged: (value) => setState(() => _choice = value),
            child: Column(
              children: [
                for (final value in ['one', 'two'])
                  RadioListTile<String>(
                    title: Text(value == 'one' ? 'Один' : 'Два'),
                    value: value,
                    enabled: !disabled,
                  ),
              ],
            ),
          ),
          'segmented' => SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: [
              ButtonSegment(
                value: 'one',
                label: const Text('Один'),
                enabled: !disabled,
              ),
              ButtonSegment(
                value: 'two',
                label: const Text('Два'),
                enabled: !disabled,
              ),
            ],
            selected: choice == 'one' || choice == 'two' ? {choice!} : {},
            onSelectionChanged: disabled
                ? null
                : (value) => setState(() => _choice = value.firstOrNull),
          ),
          _ => EnSelect(
            label: 'Выбор',
            options: empty
                ? const {}
                : {'one': widget.longText ? label : 'Один', 'two': 'Два'},
            value: choice,
            enabled: !disabled,
            onChanged: (value) => setState(() => _choice = value),
          ),
        };
        if (empty && variant != 'select') {
          example = const Text('Нет вариантов');
        } else if (choice == 'missing' && variant != 'select') {
          example = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [const Text('Неизвестное значение'), example],
          );
        }
      case 'C05':
        example = EnForm(
          canSubmit: !disabled,
          pending: pending,
          errors: state == 'error' ? const ['Ошибка owner'] : const [],
          onSubmit: _called,
          child: EnField(label: 'Название', controller: _draft),
        );
      case 'C06':
        example = EnSearch(
          controller: _draft,
          enabled: !disabled,
          onChanged: (_) => _called(),
          onClear: () {
            _draft.clear();
            _called();
          },
          activeCount: _checked ? 1 : 0,
          filters: variant == 'filters'
              ? [
                  FilterChip(
                    label: const Text('Выбранные'),
                    selected: _checked,
                    onSelected: disabled
                        ? null
                        : (value) => setState(() => _checked = value),
                  ),
                ]
              : const [],
        );
      case 'C07':
        example = EnTable(
          columns: const ['Название', 'Статус'],
          rows: empty
              ? const []
              : [
                  EnTableRow(
                    id: 'demo',
                    cells: [label, 'Пример'],
                    enabled: !disabled,
                  ),
                ],
          selected: _selected,
          onSelect: (id, value) => setState(() {
            value ? _selected.add(id) : _selected.remove(id);
            _calls++;
          }),
          onSort: (_, ascending) => _called(),
        );
      case 'C08':
        example = EnList(
          items: empty
              ? const []
              : [
                  EnListItem(
                    id: 'demo',
                    label: label,
                    description: 'Синтетическая строка',
                    enabled: !disabled,
                  ),
                ],
          selected: _choice,
          onActivate: (id) => setState(() {
            _choice = id;
            _calls++;
          }),
        );
      case 'C09':
        example = EnPager(
          loadedCount: empty ? 0 : 2,
          total: state == 'unknown'
              ? null
              : empty
              ? 0
              : 5,
          loading: pending,
          hasNext: !disabled,
          hasPrevious: !disabled,
          onNext: _called,
          onPrevious: _called,
        );
      case 'C10':
        example = EnCard(
          title: label,
          description: empty ? null : 'Пример общей секции',
          actions: variant == 'toolbar'
              ? [EnButton(label: 'Действие', onPressed: _called)]
              : const [],
          child: Text(empty ? 'Нет содержимого' : 'Синтетический slot'),
        );
      case 'C11':
        final kind = EnStatusKind.values.firstWhere(
          (value) => value.name == state,
          orElse: () => EnStatusKind.neutral,
        );
        example = EnStatus(
          label: state,
          kind: kind,
          reason: widget.longText ? label : null,
        );
      case 'C12':
        final kind = EnStatusKind.values.firstWhere(
          (value) => value.name == state,
          orElse: () => EnStatusKind.neutral,
        );
        example = variant == 'snackbar'
            ? EnButton(
                label: 'Показать сообщение',
                onPressed: () =>
                    showEnSnackBar(context, message: label, severity: kind),
              )
            : EnMessage(
                message: label,
                severity: kind,
                kind: variant == 'banner'
                    ? EnMessageKind.banner
                    : EnMessageKind.inline,
                actionLabel: 'Проверить',
                onAction: _called,
                onDismiss: _called,
              );
      case 'C13':
        example = EnRegion(
          state: EnRegionState.values.firstWhere(
            (value) => value.name == state,
          ),
          message: label,
          onRetry: state == 'loading' ? null : _called,
        );
      case 'C14':
        example = EnButton(
          label: 'Открыть диалог',
          onPressed: () async {
            await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => EnConfirmationDialog(
                title: label,
                danger: variant == 'danger',
                pending: pending,
                onConfirm: () {
                  if (state == 'error') throw StateError('Пример отказа');
                  _called();
                },
                onError: (_) => setState(() => _error = 'Пример отказа'),
                child: const Text('Только демонстрация.'),
              ),
            );
          },
        );
      case 'C15':
        example = variant == 'tooltip'
            ? EnTooltip(
                message: 'Подсказка по фокусу',
                child: IconButton(
                  onPressed: _called,
                  icon: const Icon(Icons.info_outline),
                ),
              )
            : EnMenu(
                label: 'Действия',
                enabled: !disabled,
                items: empty
                    ? const []
                    : const [
                        EnMenuAction('one', 'Открыть'),
                        EnMenuAction(
                          'two',
                          'Удалить',
                          enabled: false,
                          disabledReason: 'Недоступно',
                        ),
                      ],
                onSelected: (_) => _called(),
              );
      case 'C16':
        example = EnTabs(
          items: [
            const EnNavigationItem('one', 'Первая'),
            EnNavigationItem('two', 'Вторая', enabled: !disabled),
          ],
          selected: _choice,
          onSelect: (value) => setState(() => _choice = value),
        );
      case 'C17':
        example = SizedBox(
          height: 480,
          child: EnShell(
            items: const [
              EnNavigationItem('one', 'Раздел A'),
              EnNavigationItem('two', 'Раздел B'),
            ],
            selected: _choice,
            onSelect: (value) => setState(() => _choice = value),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: EnField(label: 'Синтетический slot', controller: _draft),
            ),
          ),
        );
      case 'C18':
        example = EnDetails(
          title: variant == 'disclosure' ? 'Подробности' : null,
          values: {
            'Название': empty
                ? ''
                : state == 'unknown'
                ? null
                : label,
          },
          expanded: _expanded,
          onExpand: (value) => setState(() => _expanded = value),
        );
      case 'C19':
        example = EnProgress(
          label: label,
          value: pending
              ? null
              : state == 'unknown'
              ? double.nan
              : state == 'completed'
              ? 1
              : .4,
        );
      case 'C20':
        example = EnMachineText(
          text: empty
              ? ''
              : widget.longText
              ? 'demo-id-' * 20
              : 'demo-id-001',
          sensitive: variant == 'sensitive',
          selectable: variant != 'plain',
          copyable: variant == 'copy',
          onCopy: (_) async {
            if (state == 'error') throw StateError('Пример отказа');
            _called();
          },
        );
      default:
        example = const Text('Неизвестный компонент');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        example,
        if (['hover', 'focus', 'pressed'].contains(state))
          const Text('Наведение / Tab / удержание: интерактивное состояние'),
        if (_error != null) Text(_error!),
        const SizedBox(height: 8),
        Text('Событий: $_calls'),
      ],
    );
  }
}
