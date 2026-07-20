Changelog
=========

v1.1.0 (2026-07-19)
-------------------

- Added support for creating views and component storage at runtime.
- Added `@:echoes_storage` metadata to allow defining custom behavior per component.
- Added `Echoes.serialize()` and `unserialize()`.
- Exposed `SystemList.update()` to allow running systems for custom amounts of time.
- Added `ComponentStorage.onError`, an alternate way to receive errors.
- Added a way to tell when a component is being replaced (see [replacing components](./README.md#replacing-components)).
- Added `Entity.beingDestroyed` property.
- Added metadata descriptions and code completion.
- Deprecated entity templates (use [echoes-templates](https://github.com/player-03/echoes-templates) instead).
- Fixed various bugs.
- Improved documentation.
- Improved error messages.
