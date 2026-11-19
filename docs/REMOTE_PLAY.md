# Playing with remote friends

Lowlight Island uses direct UDP connections: the host's PC runs the game simulation and friends connect to
its address on **UDP port 24680**. On the same Wi-Fi / LAN this just works with the host's local IP
(shown in the lobby). Across the internet, most home connections sit behind carrier-grade NAT (CGNAT), so
plain port forwarding often fails. A free mesh VPN is the default, reliable path.

## Recommended: Tailscale (free)

1. Everyone installs Tailscale from <https://tailscale.com/download> and signs in.
2. The host invites friends to their tailnet (admin console → **Share** / **Invite users**), or everyone
   joins the same account for a play session.
3. The host clicks **Host a run**. The lobby lists the host's addresses — use the one starting with
   **100.** (the Tailscale address). You can also run `tailscale ip -4` on the host.
4. Friends type that 100.x.x.x address into **Host address** and click **Join by address**.

Alternative with the same flow: **Radmin VPN** (Windows only) — create a network, friends join it, use the
host's Radmin address (26.x.x.x).

## Alternative: port forwarding

Only works if the host has a real public IPv4 address (not CGNAT).

1. Forward **UDP 24680** on the router to the host PC's local IP.
2. Allow the game through Windows Defender Firewall (Windows prompts on first host — tick *Private* and
   *Public* if you understand the risk, or add a UDP 24680 inbound rule).
3. Friends join with the host's public IP (search "what is my IP" on the host).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| "Could not reach the host" after a few seconds | Wrong address, host not hosting, firewall blocking UDP 24680, or CGNAT (use Tailscale). |
| "Version mismatch" | Everyone must run the same build. |
| "A run is already in progress" | Join while the host is in the lobby. A player who drops mid-run reconnects automatically to their slot for 2 minutes. |
| Rubber-banding | High latency or packet loss; prefer wired connections and a nearby host. |

## Milestone 2 checklist: first remote test

- [ ] Two PCs on the same Wi-Fi: host + join by LAN IP, walk around, climb, open the door.
- [ ] One PC on a different network (e.g. phone hotspot) via Tailscale: same checks.
- [ ] Note ping/feel while sprinting and climbing; report any snapping.
