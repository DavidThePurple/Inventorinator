import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'build_identity.dart';

/// Build identification beside the logo, matching the service-status labels.
class BuildCommitLabel extends StatelessWidget {
  const BuildCommitLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final hasCommit = RegExp(r'^[0-9a-f]{7,40}$')
        .hasMatch(inventorinatorBuildHash);
    final shortHash = hasCommit && inventorinatorBuildHash.length > 7
        ? inventorinatorBuildHash.substring(0, 7)
        : inventorinatorBuildHash;
    return Tooltip(
      message: [
        if (hasCommit) 'View commit $inventorinatorBuildHash on GitHub',
        if (inventorinatorHasLocalChanges) 'Includes uncommitted changes',
        if (!hasCommit) 'Local build',
      ].join('\n'),
      child: InkWell(
        onTap: hasCommit
            ? () => launchUrl(
                Uri.parse(
                  '$inventorinatorProjectUrl/commit/$inventorinatorBuildHash',
                ),
                mode: LaunchMode.externalApplication,
              )
            : null,
        child: Text(
          hasCommit ? 'Commit $shortHash' : 'Local build',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}
