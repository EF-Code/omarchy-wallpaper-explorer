# Security policy

Security fixes are supported on the latest release and the current `main`
branch.

Please report suspected vulnerabilities privately through GitHub's
**Security advisories** tab for this repository. Include the affected version,
reproduction details, impact, and any suggested mitigation. Do not open a
public issue for an unpatched vulnerability.

Wallpaper Explorer never downloads or installs themes or wallpapers. Its
security boundary begins with themes already installed for the current user.
It reads those theme wallpaper directories and copies an explicitly selected
wallpaper into plugin-owned user state before asking Omarchy to apply it. It
must not modify `/usr/share/omarchy` or switch the active theme's colors.
