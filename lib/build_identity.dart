/// Build metadata is injected by the release workflow with `--dart-define`.
/// Local development builds stay identifiable without requiring a Git checkout.
const inventorinatorReleaseVersion = String.fromEnvironment(
  'INVENTORINATOR_VERSION',
  defaultValue: 'development',
);

const inventorinatorBuildHash = String.fromEnvironment(
  'INVENTORINATOR_BUILD_HASH',
  defaultValue: 'local',
);

const inventorinatorProjectUrl =
    'https://github.com/DavidThePurple/Inventorinator';

const inventorinatorUserAgent =
    'Inventorinator/$inventorinatorReleaseVersion '
    '(build $inventorinatorBuildHash; +$inventorinatorProjectUrl)';
