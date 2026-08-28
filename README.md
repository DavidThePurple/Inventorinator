# Inventorinator

Inventorinator is a Linux-first, cross-platform workshop inventory and build
management app. It uses local SQLite for offline operation and can synchronize
multiple devices through hosted or self-hosted Supabase.

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

Android, Windows, and Linux use the same Flutter application and workshop data
format.

## Android release signing

Release builds are never signed with Flutter's shared debug key. Generate your
own upload keystore, copy `android/key.properties.example` to
`android/key.properties`, and fill in its private values. Both the properties
file and keystores are ignored by Git. A release build fails clearly when
signing has not been configured.

## Self-hosted synchronization

The Flutter app connects with a client-safe Supabase publishable key. Database
migrations are deliberately handled by the server-side Inventorinator
connector; database administrator credentials are never stored on phones or
desktop clients.

Public builds ship with no server address or key. Users enter their own hosted
or self-hosted Supabase connector details during onboarding. Maintainers may
provide deployment-specific defaults with the documented `--dart-define`
arguments.

See [Supabase self-hosting and updates](supabase/README.md) for initial setup,
Dockge integration, automatic migrations, backups, and upgrades.

## License

Inventorinator is released under the [MIT License](LICENSE). You may use,
modify, redistribute, sell, fork, and rebrand it, provided the MIT copyright
and permission notice remains included with copies of the software.
