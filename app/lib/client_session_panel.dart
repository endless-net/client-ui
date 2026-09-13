import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/widgets.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

import 'client_connection_panel.dart';
import 'client_locale.dart';
import 'client_session.dart';
import 'client_recovery_panel.dart';
import 'client_runtime_operations_panel.dart';
import 'client_profiles_panel.dart';
import 'client_create_profile_panel.dart';
import 'client_enrollment_panel.dart';
import 'client_cleanup_panel.dart';
import 'client_networks_panel.dart';
import 'client_peers_panel.dart';
import 'client_identity_panel.dart';
import 'client_diagnostics_panel.dart';
import 'client_preferences_panel.dart';
import 'client_privileged_recovery.dart';
import 'client_privileged_session.dart';
import 'client_windows_recovery.dart';
import 'client_resources_panel.dart';
import 'client_exit_panel.dart';
import 'client_update_panel.dart';
import 'client_support_panel.dart';

/// Desktop application binding. A mobile runtime adapter can supply the same
/// shared connection panel without using a desktop local channel.
class ClientSessionPanel extends StatelessWidget {
  const ClientSessionPanel({
    super.key,
    required this.session,
    this.exportBundle,
    this.elevate,
    this.uiBuild,
    this.locale = ClientLocale.en,
  });
  final ClientSession session;
  final ClientLocale locale;
  final api.BuildIdentity? uiBuild;
  final Future<ClientElevationOutcome> Function(ClientPrivilegedRecovery)?
  elevate;
  Future<ClientElevationOutcome> Function(ClientPrivilegedRecovery)?
  get _elevate =>
      elevate ?? (Platform.isWindows ? launchClientWindowsRecovery : null);
  final Future<bool> Function(String requestId, void Function() checkContext)?
  exportBundle;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClientSupportPanel(
            locale: locale,
            state: session.state,
            load: session.getSupportInfo,
            openBrowser: (uri, check) {
              check();
              return launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
          if (uiBuild != null)
            ClientUpdatePanel(
              locale: locale,
              state: session.state,
              uiBuild: uiBuild!,
              load: session.getUpdateInfo,
            ),
          ClientExitPanel(
            locale: locale,
            state: session.state,
            load: session.getExitNodes,
            select: (profile, node, mode, lan, check) => session.submit(
              api.OperationKind.OPERATION_KIND_SELECT_EXIT_NODE,
              (commands, mutation) {
                check();
                return commands.selectExitNode(
                  api.SelectExitNodeRequest(
                    mutation: mutation,
                    profile: api.ProfileRef(profileId: profile),
                    exitNodeId: node,
                    familyMode: mode,
                    lanAccess: lan,
                  ),
                );
              },
            ),
            clear: (profile, check) => session.submit(
              api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE,
              (commands, mutation) {
                check();
                return commands.clearExitNode(
                  api.ClearExitNodeRequest(
                    mutation: mutation,
                    profile: api.ProfileRef(profileId: profile),
                  ),
                );
              },
            ),
          ),
          ClientResourcesPanel(
            locale: locale,
            state: session.state,
            openBrowser: (uri, check) {
              check();
              return launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            load: (search, kinds) =>
                session.listResources(search: search, kinds: kinds),
            setEnabled: (profile, resource, enabled, check) => session.submit(
              api.OperationKind.OPERATION_KIND_SET_RESOURCE_ENABLED,
              (commands, mutation) {
                check();
                return commands.setResourceEnabled(
                  api.SetResourceEnabledRequest(
                    mutation: mutation,
                    profile: api.ProfileRef(profileId: profile),
                    resourceId: resource,
                    enabled: enabled,
                  ),
                );
              },
            ),
          ),
          ClientPreferencesPanel(
            locale: locale,
            state: session.state,
            load: session.getPreferences,
            apply: (id, patch, check) => session.submit(
              api.OperationKind.OPERATION_KIND_SET_PREFERENCES,
              (commands, mutation) {
                check();
                return commands.setPreferences(
                  api.SetPreferencesRequest(
                    mutation: mutation,
                    profile: api.ProfileRef(profileId: id),
                    patch: patch,
                  ),
                );
              },
            ),
            reset: (id, keys, check) => session.submit(
              api.OperationKind.OPERATION_KIND_RESET_PREFERENCES,
              (commands, mutation) {
                check();
                return commands.resetPreferences(
                  api.ResetPreferencesRequest(
                    mutation: mutation,
                    profile: api.ProfileRef(profileId: id),
                    keys: keys,
                  ),
                );
              },
            ),
          ),
          ClientDiagnosticsPanel(
            locale: locale,
            state: session.state,
            load: session.getDiagnostics,
            loadLogs: session.getRecentLogs,
            createBundle: (id) => session.submit(
              api.OperationKind.OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE,
              (commands, mutation) => commands.createDiagnosticsBundle(
                api.CreateDiagnosticsBundleRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(profileId: id),
                ),
              ),
            ),
          ),
          ClientIdentityPanel(
            locale: locale,
            state: session.state,
            canElevate: _elevate != null,
            load: session.getServerIdentity,
            trust: (identity) {
              final identityEpoch = session.state.domainEpoch(
                api.Domain.DOMAIN_SERVER_IDENTITY,
              );
              final profileEpoch = session.state.domainEpoch(
                api.Domain.DOMAIN_PROFILES,
              );
              if (session.state.snapshot!.runtime.callerAccess ==
                      api.Access.ACCESS_OWNER &&
                  _elevate != null) {
                return session.submitPrivilegedViaLookup(
                  api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY,
                  (mutation) {
                    if (identityEpoch !=
                            session.state.domainEpoch(
                              api.Domain.DOMAIN_SERVER_IDENTITY,
                            ) ||
                        profileEpoch !=
                            session.state.domainEpoch(
                              api.Domain.DOMAIN_PROFILES,
                            )) {
                      throw StateError('Identity changed before elevation');
                    }
                    return ClientPrivilegedRecovery.trust(
                      api.TrustServerIdentityRequest(
                        mutation: mutation,
                        profile: api.ProfileRef(profileId: identity.profileId),
                        confirmedControlOrigin: identity.controlOrigin,
                        confirmedKeyId: identity.announcedKeyId,
                        confirmedAnnouncementId: identity.announcementId,
                      ),
                    );
                  },
                  _elevate!,
                );
              }
              return session.submit(
                api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY,
                (commands, mutation) {
                  if (identityEpoch !=
                          session.state.domainEpoch(
                            api.Domain.DOMAIN_SERVER_IDENTITY,
                          ) ||
                      profileEpoch !=
                          session.state.domainEpoch(
                            api.Domain.DOMAIN_PROFILES,
                          )) {
                    throw StateError(
                      'Identity changed before trust submission',
                    );
                  }
                  return commands.trustServerIdentity(
                    api.TrustServerIdentityRequest(
                      mutation: mutation,
                      profile: api.ProfileRef(profileId: identity.profileId),
                      confirmedControlOrigin: identity.controlOrigin,
                      confirmedKeyId: identity.announcedKeyId,
                      confirmedAnnouncementId: identity.announcementId,
                    ),
                  );
                },
              );
            },
          ),
          ClientNetworksPanel(
            locale: locale,
            state: session.state,
            load: session.listNetworks,
            select: (profileId, networkId) => session.submit(
              api.OperationKind.OPERATION_KIND_SELECT_NETWORK,
              (commands, mutation) => commands.selectNetwork(
                api.SelectNetworkRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(profileId: profileId),
                  networkId: networkId,
                ),
              ),
            ),
          ),
          ClientPeersPanel(
            locale: locale,
            state: session.state,
            load: (search) => session.listPeers(search: search),
          ),
          ClientCleanupPanel(
            locale: locale,
            state: session.state,
            canElevate: _elevate != null,
            logout: (id) => session.submit(
              api.OperationKind.OPERATION_KIND_LOGOUT,
              (commands, mutation) => commands.logout(
                api.LogoutRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(profileId: id),
                ),
              ),
            ),
            forget: (id) {
              if (session.state.snapshot!.runtime.callerAccess ==
                      api.Access.ACCESS_OWNER &&
                  _elevate != null) {
                return session.submitPrivilegedViaLookup(
                  api.OperationKind.OPERATION_KIND_FORGET_LOCAL_ENROLLMENT,
                  (mutation) => ClientPrivilegedRecovery.forget(
                    api.ForgetLocalEnrollmentRequest(
                      mutation: mutation,
                      profile: api.ProfileRef(profileId: id),
                      confirmed: true,
                    ),
                  ),
                  _elevate!,
                );
              }
              return session.submit(
                api.OperationKind.OPERATION_KIND_FORGET_LOCAL_ENROLLMENT,
                (commands, mutation) => commands.forgetLocalEnrollment(
                  api.ForgetLocalEnrollmentRequest(
                    mutation: mutation,
                    profile: api.ProfileRef(profileId: id),
                    confirmed: true,
                  ),
                ),
              );
            },
          ),
          ClientEnrollmentPanel(
            locale: locale,
            state: session.state,
            enroll: (id, mode, hostname, token) => session.submit(
              api.OperationKind.OPERATION_KIND_ENROLL,
              (commands, mutation) {
                final request = api.EnrollRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(profileId: id),
                  mode: mode,
                  hostname: hostname,
                );
                if (token == null) {
                  request.browserLogin = true;
                } else {
                  request.enrollmentToken = token;
                }
                return commands.enroll(request);
              },
            ),
          ),
          ClientCreateProfilePanel(
            locale: locale,
            state: session.state,
            create: (name, origin) => session.submit(
              api.OperationKind.OPERATION_KIND_CREATE_PROFILE,
              (commands, mutation) => commands.createProfile(
                api.CreateProfileRequest(
                  mutation: mutation,
                  displayName: name,
                  controlOrigin: origin,
                ),
              ),
            ),
          ),
          ClientConnectionPanel(
            locale: locale,
            state: session.state,
            renewSession: () => session.submit(
              api.OperationKind.OPERATION_KIND_RENEW_SESSION,
              (commands, mutation) => commands.renewSession(
                api.RenewSessionRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(
                    profileId: session.state.snapshot!.status.activeProfileId,
                  ),
                ),
              ),
            ),
            connect: () => session.submit(
              api.OperationKind.OPERATION_KIND_CONNECT,
              (commands, mutation) {
                return commands.connect(
                  api.ConnectRequest(
                    mutation: mutation,
                    profile: api.ProfileRef(
                      profileId: session.state.snapshot!.status.activeProfileId,
                    ),
                  ),
                );
              },
            ),
            disconnect: () => session.submit(
              api.OperationKind.OPERATION_KIND_DISCONNECT,
              (commands, mutation) {
                return commands.disconnect(
                  api.DisconnectRequest(
                    mutation: mutation,
                    profile: api.ProfileRef(
                      profileId: session.state.snapshot!.status.activeProfileId,
                    ),
                  ),
                );
              },
            ),
          ),
          ClientRuntimeOperationsPanel(locale: locale, state: session.state),
          ClientRecoveryPanel(
            locale: locale,
            // Local-journal recovery stays separate from stream observations.
            exportBundle: exportBundle,
            state: session.state,
            recover: session.recoverPending,
            acknowledge: session.journal.acknowledge,
            openBrowser: (uri) =>
                launchUrl(uri, mode: LaunchMode.externalApplication),
          ),
          ClientProfilesPanel(
            locale: locale,
            state: session.state,
            load: session.listProfiles,
            remove: (id) => session.submit(
              api.OperationKind.OPERATION_KIND_REMOVE_PROFILE,
              (commands, mutation) => commands.removeProfile(
                api.RemoveProfileRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(profileId: id),
                ),
              ),
            ),
            rename: (id, name) => session.submit(
              api.OperationKind.OPERATION_KIND_RENAME_PROFILE,
              (commands, mutation) => commands.renameProfile(
                api.RenameProfileRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(profileId: id),
                  displayName: name,
                ),
              ),
            ),
            select: (id) => session.submit(
              api.OperationKind.OPERATION_KIND_SELECT_PROFILE,
              (commands, mutation) => commands.selectProfile(
                api.SelectProfileRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(profileId: id),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
