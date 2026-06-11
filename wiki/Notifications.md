# Notifications

Oven can notify you when long-running operations finish — base VM builds, IPSW downloads, registry pushes and pulls, and VM state changes.

---

## Notification Channels

| Channel | Requires |
|---|---|
| macOS system notifications | Nothing extra; enable in macOS System Settings → Notifications |
| Pushover | Pushover account + app API token + user key |
| Slack | Incoming webhook URL |
| Microsoft Teams | Incoming webhook URL |

You can enable multiple channels simultaneously.

---

## Setting Up Notifications

Go to [Preferences → Notifications](Preferences#notifications).

### macOS System Notifications

Toggle **System Notifications** on. If Oven doesn't appear in System Settings → Notifications, launch it once and the permission prompt will appear.

### Pushover

1. Create an application at [pushover.net](https://pushover.net/apps/build).
2. Copy the **API Token** and your **User Key**.
3. In Preferences → Notifications, enable **Pushover** and paste both values.
4. Click **Test** to send a test notification.

### Slack

1. In your Slack workspace, create an **Incoming Webhook** (Apps → Incoming Webhooks → Add to Slack).
2. Copy the webhook URL (format: `https://hooks.slack.com/services/...`).
3. In Preferences → Notifications, enable **Slack** and paste the URL.
4. Click **Test** to verify.

### Microsoft Teams

1. In your Teams channel, add the **Incoming Webhook** connector.
2. Copy the webhook URL.
3. In Preferences → Notifications, enable **Teams** and paste the URL.
4. Click **Test** to verify.

---

## Notification Events

Configure which events trigger notifications in Preferences → Notifications. Each event can be toggled independently per channel.

| Event | Triggered When |
|---|---|
| **Base VM Build Success** | A Packer build completes without errors |
| **Base VM Build Failure** | A Packer build exits with an error |
| **IPSW Download Complete** | A firmware file finishes downloading |
| **Registry Push Complete** | A `tart push` operation completes |
| **Registry Pull Complete** | A `tart pull` or `tart clone` operation completes |
| **VM Stopped** | A running VM is stopped (manually or after a build completion action) |

---

## Build Monitoring & Timeouts

Oven monitors active builds for signs of stall. Configure these in [Preferences → Build](Preferences#build):

- **Build Timeout** — if a build produces no output for this many minutes, Oven treats it as hung and fires a failure notification
- **Heartbeat Interval** — how often Oven checks for build progress

If a build times out, Oven logs the event and sends a failure notification through all enabled channels.

---

## Notification Content

Notifications include:
- The event type (build success, failure, etc.)
- The Base VM or VM name
- Duration of the operation (where applicable)
- A brief description of what happened

Slack and Teams notifications are formatted with Markdown; Pushover and system notifications use plain text.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| No macOS notifications appear | Open System Settings → Notifications → Oven and check that Allow Notifications is on |
| Pushover test fails | Double-check API token and user key — they are different values |
| Slack webhook returns `no_service` | The webhook may have been disabled; recreate it in Slack |
| Notifications fire for all VMs | Check per-event toggles — events are global, not per-VM |
