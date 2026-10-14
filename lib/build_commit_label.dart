import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'build_identity.dart';

const _previousRelease = '0.1.1-alpha';

/// Keep this concise release digest aligned with the unreleased changelog.
/// It is intentionally in-app so the build marker still explains itself
/// without making the user leave Inventorinator.
const _releaseHighlights = <String>[
  'Protected shared sync, deletes, and stock locations against stale devices.',
  'Added shared checkout tracking and labeled machine timers.',
  'Added optional PIN locking and secure system-keyring token storage.',
  'Added reviewed CSV/XLSX/JSON import, portable export, and batch undo.',
  'Bulk Import can now import an entire kit and its BOM.',
  'Added Stockroom location tools and the Orphaned Items audit/assignment flow.',
  'Added webcam scanner recovery plus Windows label OCR.',
  'Added the InventoryCraft theme, wallpapers, background patterns, and drag rails.',
  'Reworked desktop item details, bulk actions, and right-click actions.',
  'Expanded supplier import/search, including LDO, Adafruit, BIQU, E3D, Polymaker, Printed Solid, and Slice.',
];

/// Build identification beside the logo, matching the service-status labels.
class BuildCommitLabel extends StatelessWidget {
  const BuildCommitLabel({
    super.key,
    this.inventoryCraft = false,
    this.framed = true,
  });

  final bool inventoryCraft;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final hasCommit = RegExp(r'^[0-9a-f]{7,40}$')
        .hasMatch(inventorinatorBuildHash);
    final shortHash = hasCommit && inventorinatorBuildHash.length > 7
        ? inventorinatorBuildHash.substring(0, 7)
        : inventorinatorBuildHash;
    final releaseNotes = [
      'BUILD // ${hasCommit ? shortHash : 'LOCAL'}',
      'Changes since $_previousRelease:',
      ..._releaseHighlights.map((highlight) => '• $highlight'),
      if (inventorinatorHasLocalChanges)
        '• Includes uncommitted local changes.',
      if (hasCommit) 'Click for the full changelog.',
    ].join('\n');
    return Tooltip(
      message: releaseNotes,
      child: Semantics(
        label: releaseNotes.replaceAll('\n', ' '),
        button: hasCommit,
        child: InkWell(
          onTap: hasCommit
              ? () => launchUrl(
                  Uri.parse(
                    '$inventorinatorProjectUrl/blob/'
                    '$inventorinatorBuildHash/CHANGELOG.md',
                  ),
                  mode: LaunchMode.externalApplication,
                )
              : null,
          child: Container(
            height: inventoryCraft && framed ? 40 : null,
            alignment: inventoryCraft && framed ? Alignment.center : null,
            padding: inventoryCraft && framed
                ? const EdgeInsets.symmetric(horizontal: 10)
                : EdgeInsets.zero,
            decoration: inventoryCraft && framed
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: .62),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  )
                : null,
            child: Text(
              inventoryCraft
                  ? 'BUILD // ${hasCommit ? shortHash : 'LOCAL'}'
                  : hasCommit
                  ? 'Commit $shortHash'
                  : 'Local build',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: inventoryCraft
                    ? Theme.of(context).colorScheme.onSurface
                    : null,
                fontFamily: inventoryCraft ? 'monospace' : null,
                fontSize: inventoryCraft ? 12 : null,
                fontWeight: inventoryCraft ? FontWeight.w800 : null,
                letterSpacing: inventoryCraft ? .7 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
