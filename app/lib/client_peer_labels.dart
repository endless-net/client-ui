import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_locale.dart';

String peerSnapshotLabel(api.AgentSnapshotState value, ClientLocale locale) =>
    switch (value) {
      api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_ABSENT => locale.text(
        en: 'Absent',
        ru: 'Отсутствует',
      ),
      api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_CURRENT => locale.text(
        en: 'Current',
        ru: 'Текущее',
      ),
      api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_PREVIOUS => locale.text(
        en: 'Previous',
        ru: 'Предыдущее',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };

String peerPathLabel(api.PathKind value, ClientLocale locale) =>
    switch (value) {
      api.PathKind.PATH_KIND_DIRECT => locale.text(en: 'Direct', ru: 'Прямой'),
      api.PathKind.PATH_KIND_RELAY => locale.text(
        en: 'Relay',
        ru: 'Через ретранслятор',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указан'),
    };

String peerHealthLabel(api.PathHealth value, ClientLocale locale) =>
    switch (value) {
      api.PathHealth.PATH_HEALTH_UNKNOWN => locale.text(
        en: 'Unknown',
        ru: 'Неизвестно',
      ),
      api.PathHealth.PATH_HEALTH_CHECKING => locale.text(
        en: 'Checking',
        ru: 'Проверяется',
      ),
      api.PathHealth.PATH_HEALTH_REACHABLE => locale.text(
        en: 'Reachable',
        ru: 'Доступен',
      ),
      api.PathHealth.PATH_HEALTH_UNREACHABLE => locale.text(
        en: 'Unreachable',
        ru: 'Недоступен',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };
