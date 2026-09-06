# Security policy

## Supported versions

Only the latest release on the [Releases page](https://github.com/nabeeltahirdeveloper/peekbar/releases) receives fixes.

## What PeekBar can access

PeekBar asks for Screen Recording (to draw the real icons of other apps' status items)
and Accessibility (to press those items on your behalf and identify their owning app).
It reads system metrics through Mach, sysctl, IOKit and the SMC user client, read-only.
It makes no network requests except the optional public IP lookup, which is off by default.
Nothing is stored beyond local preferences.

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's private
[security advisory form](https://github.com/nabeeltahirdeveloper/peekbar/security/advisories/new)
for this repository. You'll get an acknowledgement within a few days and a fix or
mitigation plan as soon as the issue is confirmed.
