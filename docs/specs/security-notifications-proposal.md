# Security Notifications Proposal

## Summary

Talkie pairing should produce visible security events, not silent state changes.
The goal is to make trust expansion legible across the user's Talkie devices
without turning pairing into a heavy approval workflow by default.

This spec proposes a two-tier delivery model:

- Tier 1 uses CloudKit identity and push/synced state when the user is on the
  cloud-backed Talkie path.
- Tier 2 uses local/direct device delivery when devices are paired directly or
  connected over the bridge without CloudKit.

## Security Event Model

Security events are small, append-only records with enough metadata to explain
what happened and where it should appear.

Recommended fields:

- `id`
- `type`
- `createdAt`
- `actorSurface` (`mac`, `ios`, `ipad`, `cli`)
- `sourceDeviceId`
- `sourceDeviceName`
- `targetDeviceId` or `targetMacName` when relevant
- `severity` (`info`, `attention`, `warning`)
- `status` (`created`, `delivered`, `acknowledged`, `expired`)
- `summary`
- `details`

Security events should be durable enough to sync, but small enough to display
as a timeline item or banner.

## Event Types

Bridge pairing events:

- `bridge_pair_requested`
- `bridge_pair_approved`
- `bridge_pair_completed`
- `bridge_pair_removed`

SSH terminal events:

- `ssh_terminal_key_prepared`
- `ssh_terminal_remote_login_checked`
- `ssh_terminal_payload_created`
- `ssh_terminal_imported`
- `ssh_terminal_connected`

Optional follow-up events may include `bridge_device_removed`,
`bridge_device_expired`, or `ssh_terminal_revoked`.

## Tier 1: CloudKit Push and Synced Identity

When the user is signed into the cloud-backed Talkie identity, security events
should be written to the private CloudKit-backed event stream.

Behavior:

- events sync across the user's Talkie devices
- CloudKit can trigger push delivery for new events
- the Mac, iPhone, and iPad can all show the same event history
- events should survive app restarts and delayed device reconnects

This tier is the best default for users who already rely on Talkie sync.

## Tier 2: Local and Direct Paired Devices

When CloudKit is unavailable or disabled, Talkie should still surface pairing
activity through local and direct connected devices.

Behavior:

- the Mac records the event locally
- currently connected paired devices receive the event immediately when
  possible
- reconnecting devices fetch unread events later
- the originating Mac keeps the event visible until it is acknowledged

This tier should use the existing bridge or direct device channel instead of a
new transport. It is best-effort delivery, not a guaranteed push system.

## Delivery and Acknowledgement

Delivery states:

- `created` when the event is generated
- `delivered` when at least one target surface has received it
- `acknowledged` when the user dismisses or clears it on a device
- `expired` when it is old enough to stop surfacing as a live alert

Suggested UX:

- Mac shows an in-app banner or timeline entry immediately
- other connected Talkie devices show a subtle alert or inbox item
- a pairing-related event can remain visible until explicitly dismissed

## Privacy and Security Principles

- Never broadcast secret material in the event payload.
- Do not include private keys, tokens, or raw auth material in notifications.
- Prefer readable summaries over verbose protocol dumps.
- Keep bridge-only delivery limited to the user's own devices and identities.
- Let the user see what was paired, from where, and when.
- Make approval optional for Bridge pairing, but always visible.

## Phased Implementation

Phase 1:

- add the event model and local persistence on the Mac side
- surface pairing and terminal events in the Mac UI
- deliver events to connected paired devices through existing bridge state

Phase 2:

- sync security events through CloudKit for signed-in users
- add push-backed delivery across all Talkie devices
- add an in-app security timeline and acknowledgment controls

Phase 3:

- add optional require-approval flows for sensitive pairings
- add event filtering, retention rules, and device-level notification
  preferences

## Non-Goals

- replacing pairing with a separate auth system
- blocking local shell users from creating their own trust changes
- turning every pairing step into a modal approval gate

The intent is visibility first, with stronger approval and retention controls
layered on afterward.
