# Contributing

Issues and pull requests are welcome. Keep data formats generic and preserve
offline SQLite operation; no hosted service may be required for basic use.

Before submitting a change:

```sh
flutter pub get
flutter analyze
flutter test
flutter build linux --release
```

Also build the platform you changed. Windows contributors can run
`tool/build_windows.ps1`. Android release signing is intentionally maintainer
controlled; contributors may use a debug APK.

Do not commit credentials, local Supabase configuration, signing keystores,
database exports, customer inventory, product images, or captured labels.
Database changes belong in a new numbered, idempotent migration under
`supabase/migrations/`; never rewrite a migration already released.
