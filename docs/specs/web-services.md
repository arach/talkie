# Web Services Architecture

Talkie's cloud infrastructure organized by subdomain.

## Domain Map

```
                                 useTalkie.com
                                       │
  ┌────────┬────────┬──────────┬───────┼───────┬────────┬────────┐
  │        │        │          │       │       │        │        │
 go.    clerk.  accounts.    my.    cloud.   api.    admin.
  │        │        │          │       │       │        │
┌─┴─┐  ┌───┴───┐ ┌──┴──┐  ┌────┴────┐ ┌┴──┐ ┌──┴──┐ ┌───┴───┐
│Mkt│  │Clerk  │ │Clerk│  │  User   │ │Syn│ │ API │ │ Admin │
│   │  │ API   │ │ UI  │  │ Portal  │ │   │ │     │ │       │
└───┘  └───────┘ └─────┘  └─────────┘ └───┘ └─────┘ └───────┘
```

## Subdomains

### go.useTalkie.com

**Purpose**: Public-facing, no authentication

- Landing pages
- Marketing campaigns
- Short links / go-links
- Public documentation
- Download links

**Tech**: Static site (Vercel/Cloudflare Pages)

---

### clerk.useTalkie.com

**Purpose**: Clerk Frontend API

- SDK API calls
- Token verification
- Session management

**Tech**: Clerk infrastructure (CNAME → `frontend-api.clerk.services`)

---

### accounts.useTalkie.com

**Purpose**: Clerk Account Portal (sign-in/sign-up UI)

- Sign in with Apple
- Sign in with GitHub
- Email/password authentication
- OAuth flows

**Tech**: Clerk infrastructure (CNAME → `accounts.clerk.services`)

**Note**: This is NOT our code - just a DNS pointer to Clerk's hosted auth pages with our branding.

---

### my.useTalkie.com

**Purpose**: User portal (our code, uses Clerk for auth)

- Account settings
- Subscription management
- Device list
- Usage dashboard
- Profile settings
- Web-based memo viewer (future)

**Tech**: Next.js + Clerk SDK (`services/talkie-portal`)

**Auth**: Clerk (redirects to accounts.useTalkie.com for sign-in)

---

### cloud.useTalkie.com

**Purpose**: Sync and cloud services gateway

- Device handshake / pairing
- Sync status and history
- Cloud storage orchestration
- Web-based memo viewer
- Export / import tools

**Tech**: Hono/Bun or Next.js API routes

**Auth**: API tokens (issued via my.useTalkie.com)

---

### api.useTalkie.com

**Purpose**: Backend API for native apps

- User authentication verification
- Entitlements and feature flags
- Plan management
- Usage tracking
- Webhook handlers

**Tech**: Hono on Vercel (`services/talkie-api`)

**Auth**: Bearer tokens (Clerk JWT)

**Current mapping**: `talkie-api.vercel.app`

---

### admin.useTalkie.com

**Purpose**: Internal admin dashboard

- User management
- Subscription overrides
- Feature flag control
- Analytics dashboard
- Support tools

**Tech**: Next.js (`services/talkie-admin`)

**Auth**: Internal (Clerk with org restrictions)

---

## Auth Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     Native App (apps/macos/iOS)                      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ 1. User taps "Sign In"
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   accounts.useTalkie.com                            │
│                                                                 │
│   Clerk hosted UI (CNAME to Clerk infrastructure)               │
│   - Sign in with Apple                                          │
│   - Sign in with GitHub                                         │
│   - Email/password                                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ 2. Auth complete, redirect
                             │    talkie://auth/callback?__session=<token>
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Native App                                  │
│                                                                 │
│   - Receives token via URL scheme                               │
│   - Stores in Keychain                                          │
│   - Fetches user info from api.useTalkie.com                    │
└─────────────────────────────────────────────────────────────────┘
```

## Web Portal Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              User visits my.useTalkie.com                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ 1. Not authenticated?
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   accounts.useTalkie.com                            │
│                                                                 │
│   Clerk redirects here for sign-in                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ 2. Auth complete, redirect back
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   my.useTalkie.com                              │
│                                                                 │
│   User portal with authenticated session                        │
│   - Account settings                                            │
│   - Device list                                                 │
│   - Usage dashboard                                             │
└─────────────────────────────────────────────────────────────────┘
```

## Service Directory

| Service | Repo Path | Deployed To |
|---------|-----------|-------------|
| talkie-api | `services/talkie-api` | Vercel → api.useTalkie.com |
| talkie-admin | `services/talkie-admin` | Vercel → admin.useTalkie.com |
| talkie-reporter | `services/talkie-reporter` | (TBD) |

## Environment Variables

### talkie-api

```bash
CLERK_SECRET_KEY=sk_...
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_...
```

### Native Apps

Domains are hardcoded in `AuthManager.swift`:

```swift
private let clerkDomain = "https://my.useTalkie.com"  // prod
private let apiBaseURL = "https://api.useTalkie.com"
```

## DNS Configuration

| Record | Type | Value |
|--------|------|-------|
| `api.useTalkie.com` | CNAME | `cname.vercel-dns.com` |
| `my.useTalkie.com` | CNAME | (from Clerk dashboard) |
| `admin.useTalkie.com` | CNAME | `cname.vercel-dns.com` |
| `go.useTalkie.com` | CNAME | (TBD) |
| `cloud.useTalkie.com` | CNAME | (TBD) |

## Rollout Status

- [x] api.useTalkie.com - Active (talkie-api)
- [x] clerk.useTalkie.com - Verified (Clerk Frontend API)
- [x] accounts.useTalkie.com - Verified (Clerk Account Portal)
- [ ] my.useTalkie.com - Create talkie-portal
- [ ] admin.useTalkie.com - Deploy talkie-admin
- [ ] go.useTalkie.com - Create landing site
- [ ] cloud.useTalkie.com - Build sync router

## Service Directory

| Service | Repo Path | Deployed To | Status |
|---------|-----------|-------------|--------|
| talkie-api | `services/talkie-api` | api.useTalkie.com | ✅ Active |
| talkie-portal | `services/talkie-portal` | my.useTalkie.com | 📋 To create |
| talkie-admin | `services/talkie-admin` | admin.useTalkie.com | 📋 Planned |
| talkie-reporter | `services/talkie-reporter` | (TBD) | 📋 Planned |
