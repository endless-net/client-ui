import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'client_connection_panel.dart';
import 'client_session.dart';
import 'client_recovery_panel.dart';
import 'client_profiles_panel.dart';
import 'client_create_profile_panel.dart';
import 'client_enrollment_panel.dart';
import 'client_cleanup_panel.dart';
import 'client_networks_panel.dart';
import 'client_identity_panel.dart';
import 'client_diagnostics_panel.dart';

/// Desktop application binding. A mobile runtime adapter can supply the same
/// shared connection panel without using a desktop local channel.
class ClientSessionPanel extends StatelessWidget {
  const ClientSessionPanel({super.key, required this.session});
  final ClientSession session;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClientDiagnosticsPanel(
            state: session.state,
            load: session.getDiagnostics,
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
            state: session.state,
            load: session.getServerIdentity,
            trust: (identity) {
              final identityEpoch = session.state.domainEpoch(
                api.Domain.DOMAIN_SERVER_IDENTITY,
              );
              final profileEpoch = session.state.domainEpoch(
                api.Domain.DOMAIN_PROFILES,
              );
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
          ClientCleanupPanel(
            state: session.state,
            logout: (id) => session.submit(
              api.OperationKind.OPERATION_KIND_LOGOUT,
              (commands, mutation) => commands.logout(
                api.LogoutRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(profileId: id),
                ),
              ),
            ),
            forget: (id) => session.submit(
              api.OperationKind.OPERATION_KIND_FORGET_LOCAL_ENROLLMENT,
              (commands, mutation) => commands.forgetLocalEnrollment(
                api.ForgetLocalEnrollmentRequest(
                  mutation: mutation,
                  profile: api.ProfileRef(profileId: id),
                  confirmed: true,
                ),
              ),
            ),
          ),
          ClientEnrollmentPanel(
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
          ClientRecoveryPanel(
            state: session.state,
            recover: session.recoverPending,
            acknowledge: session.journal.acknowledge,
            openBrowser: (uri) =>
                launchUrl(uri, mode: LaunchMode.externalApplication),
          ),
          ClientProfilesPanel(
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
