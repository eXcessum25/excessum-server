# Hermes access layer

Sets up the `hermes` system user and everything it needs to act as a restricted,
non-root caretaker for this server: filesystem ACLs, a filtered Docker proxy, and a
narrow sudoers file. Run as root, after `03-docker.sh` and after the repo has been
cloned to its final location (needs `/srv/excessum-server` to exist; ACLs on
secrets created by services only take effect once those files actually exist, so
re-run `01-acls.sh` after the stack has been up a while too -- see "Known gaps"
below).

```
sudo ./install.sh
```

or run the numbered scripts individually (`00-user.sh`, `01-acls.sh`,
`02-docker-proxy.sh`, `03-sudoers.sh`) -- each is idempotent on its own.

## What this does NOT cover

- **Installing the `hermes-agent` CLI itself**, or configuring the Claude
  Subscription DirectSDK plugin. That's the vendor's own installer, run as the
  `hermes` user (`sudo -iu hermes`, then follow NousResearch's install docs).
- **The Hermes gateway systemd service** (`hermes gateway install --system
  --run-as-user hermes`). As of writing this hits a real snag: the hermes CLI's
  own ownership safety check wants to run as root, but a system-level gateway
  install also wants to run AS hermes -- those two requirements fight each other.
  The resolution we were leaning towards (not yet executed/confirmed) was a
  temporary `chown root:root` on the checkout immediately before the install,
  then `chown hermes:hermes` back immediately after -- satisfying the tool's own
  precondition with access root already has, not a permissions bypass. Check
  NousResearch's issue tracker for `--run-as-user` before repeating this; it may
  have a cleaner fix by the time you read this.

## The model

hermes gets broad read/write across `/srv/excessum-server` (it needs that to
actually fix things) with specific secrets/live-databases denied individually,
rather than a narrower allowlist. This was a deliberate choice (`patch per
finding, keep the broad grant`), not an oversight -- it trades a known, ongoing
cost (see below) for hermes being useful without constant allowlist maintenance.

Docker access goes through a filtered proxy (`wollomatic/socket-proxy`) on
`127.0.0.1:2375`, never the raw socket or the `docker` group (both are
root-equivalent). It allows: listing/inspecting containers, images and volumes;
reading logs and stats; restart/start/stop; and housekeeping deletes (stopped
containers, unreferenced images/volumes, dangling-image prune) -- each DELETE
route only matches with no query string, which blocks `-f`/`force=1`, so the
daemon's own "refuse to delete something in use" behaviour does the rest. Still
blocked: exec/create/run/cp, container inspect (leaks every container's env
vars -- that's the one that bit us when we trialled `tecnativa/docker-socket-proxy`,
which can only gate whole API sections, not individual routes), archive/export,
`system prune -a`, networks, swarm.

sudo access is limited to three things: `smartctl -a` on exact disk devices (no
wildcard trailing args -- that would let `-s off` through), `ufw status`, and
`/usr/local/sbin/hermes-systemctl-status` (validates every argument so
`-H user@host` can't make root open an SSH connection).

## Known gaps (accepted, not bugs)

- **The broad ACL grant on `docker/config/` will re-expose new secrets** as
  services create them (new API keys, new DBs). Three rounds of Hermes's own
  self-audit each found a fresh batch the first few rounds missed. There's no
  algorithmic fix for this under the "broad grant" model -- it needs an actual
  human (or Hermes) re-check periodically, or after adding a new service.
  Switching `docker/config/` to a deny-by-default allowlist was considered and
  explicitly declined.
- **Fixing ownership of new root/uid-owned files** that containers create over
  time under `docker/config/` isn't automated. `01-acls.sh` is safe to re-run any
  time; there's no timer/cron doing it automatically yet.
- `docker/config/immich-db` (Immich's live Postgres data, bind-mounted straight
  into the running container) is deliberately excluded from the broad grant.
  **Never widen hermes's access to it** -- changing ownership or ACLs on a live
  database's data directory can corrupt it.
