# tp7 — Waiting Room Queue (multi-user & multi-tenant)

Workshop 7: the TP6 resilient waiting queue extended with **multi-user
authentication** and **multi-tenant workspaces**. Built with Flutter and
Supabase.

Each signed-in user belongs to one or more workspaces (tenants). The queue is
shared inside a workspace and isolated from every other workspace. Users can
switch workspaces from the app bar; a new workspace can be created from the
empty state.

## Features

TP6 features are preserved (optional geolocation, offline SQLite queue,
automatic sync with deduplication, pagination, realtime inserts, connectivity
states and tests) and extended with:

- Email/password sign-up and sign-in through Supabase Auth
- Session restore on launch and explicit sign-out
- User display name from auth metadata
- Workspaces (tenants) with membership roles (`owner`, `admin`, `member`)
- Workspace switcher in the queue screen and workspace creation flow
- Per-user/per-tenant data isolation enforced by Supabase RLS
- Offline records scoped by `owner_id` + `tenant_id` so two accounts on the
  same device never sync each other's queue

## Architecture

```
lib/
├── main.dart                       Supabase init + provider wiring
├── models/                         Client, AppUser, Tenant, queue state, ...
├── providers/                      AuthProvider, TenantProvider, QueueProvider, ...
├── services/                       Auth/Tenant abstractions + Supabase implementations,
│                                   Geolocation, Connectivity, Sync
├── repositories/                   QueueRepository (+ Supabase remote data source)
├── storage/                        LocalQueueStorage (SQLite, scoped per user/tenant)
├── screens/                        SessionGate, AuthScreen, TenantSetupScreen, QueueScreen
└── widgets/                        ClientCard, OfflineBanner, LoadingWidget, ...
```

## Configuration

The app reads its Supabase credentials from `--dart-define`:

```powershell
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co `
            --dart-define=SUPABASE_ANON_KEY=your-publishable-or-anon-key
```

VS Code: use the preconfigured `tp7 (Android)` / `tp7 (Windows)` launch
profiles in `.vscode/launch.json`.

In Supabase, enable Email auth under **Authentication → Providers → Email**.
If email confirmation is enabled, confirm the account before signing in.

## Supabase setup

Apply the SQL in `supabase/migrations/` in order via the Supabase SQL editor:

1. `0001_add_location_columns.sql` — location columns and constraints.
2. `0002_register_queue_client_function.sql` — TP6 queue registration RPC.
3. `0003_multi_user_multi_tenant.sql` — tenants, memberships, RLS, and the
   tenant-aware replacement for `register_queue_client`.

Migration 0003 backfills existing clients into a `Default` workspace and adds
every existing auth user to it. If the TP6 project had permissive policies on
`public.clients`, remove them after applying the migration; the `tp7_*`
policies are the ones that enforce workspace isolation.

## Data model

- `public.tenants(id, name, created_by, created_at)`
- `public.tenant_members(tenant_id, user_id, role, created_at)`
- `public.clients` gains `owner_id` and `tenant_id`
- RPCs: `list_my_tenants`, `create_tenant`, `register_queue_client(..., p_tenant_id)`

RLS allows a user to read only clients in workspaces they belong to, and to
insert only rows owned by themselves inside one of those workspaces.

## Running the tests

```powershell
flutter analyze
flutter test
```
