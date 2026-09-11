# Nx Panel

Nx Panel (NXDactyl) is a free, open-source game server management panel based on the Pterodactyl Panel codebase.

The project keeps the upstream architecture and technical implementation where it is required for compatibility, while the user-facing product identity is **Nx Panel / NxDactyl**.

## Project identity

- Product name: **Nx Panel**
- Project codename: **NXDactyl**
- Repository: `NyroxYT/panel`
- Upstream base: Pterodactyl Panel
- License: MIT

## Branding policy

User-facing branding is being migrated to Nx Panel. This includes the application name, Composer package identity, mail sender name, documentation, logos, and UI branding.

Technical identifiers that are required for the application to work are intentionally not renamed blindly. In particular, the existing PHP namespace and internal class references remain unchanged until there is a complete, tested namespace migration. This prevents a cosmetic rebrand from breaking the panel.

Original copyright, license, and attribution notices are retained as required by the upstream license.

## Architecture

Nx Panel is being developed as a multi-repository project:

1. `nx-panel` / this repository — web panel and API
2. `nx-wings` — server control plane / daemon
3. `nx-game-eggs` — game server egg definitions

Game eggs will be imported into the Nx Panel ecosystem separately. We do not need to carry the upstream eggs repository contents into this panel repository.

## Development

The panel is the real application source, not a static mockup. It retains the Laravel/React architecture, API, authentication, server management, console, files, backups, schedules, allocations, nodes, and other core functionality from the upstream codebase while Nx-specific branding and functionality are added incrementally.

## License

Nx Panel is released under the MIT License. Upstream copyright and attribution notices remain in the repository.
