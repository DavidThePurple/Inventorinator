# Contributing

Issues and pull requests are welcome. Keep data formats generic and preserve
offline SQLite operation; no hosted service may be required for basic use.

Development environment and build instructions are maintained in the
[Inventorinator Wiki](https://github.com/DavidThePurple/Inventorinator/wiki).
Before submitting a change, run the documented analysis and test checks and
verify the platform you changed. Android release signing is intentionally
maintainer controlled; contributors may use a debug APK.

Do not commit credentials, local Supabase configuration, signing keystores,
database exports, customer inventory, product images, or captured labels.
Database changes belong in a new numbered, idempotent migration under
`supabase/migrations/`; never rewrite a migration already released.
