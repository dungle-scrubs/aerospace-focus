# Changelog

## [0.1.5](https://github.com/dungle-scrubs/aerospace-focus/compare/v0.1.4...v0.1.5) (2026-02-15)


### Features

* auto-exclude floating apps from aerospace config ([70b2ae5](https://github.com/dungle-scrubs/aerospace-focus/commit/70b2ae5f75df10072a67ed8278db5a71da075102))
* detect window geometry changes for retiling updates ([7cffb95](https://github.com/dungle-scrubs/aerospace-focus/commit/7cffb950ba609452f0f1007e951ec89521227412))
* hide focus bar when only one window on workspace ([7763bf3](https://github.com/dungle-scrubs/aerospace-focus/commit/7763bf3370574d06bf2c310f0d5a11d0bac38574))
* IPC error responses, socket probing, daemon auto-start ([2919a4b](https://github.com/dungle-scrubs/aerospace-focus/commit/2919a4b7b1206e80ce533e46e3c8718448f3b800))


### Bug Fixes

* add signal handlers and fix Mission Control race condition ([6a8ecb3](https://github.com/dungle-scrubs/aerospace-focus/commit/6a8ecb3767f221a388a4e0ccb96077d5bb56cbcb))
* hide bar during Mission Control to prevent incorrect positioning ([821dd81](https://github.com/dungle-scrubs/aerospace-focus/commit/821dd81ba4b6c3d7500a0894dde5f2bb46b343e0))
* pre-compile regexes, validate config, parse aerospace TOML once ([3cf9009](https://github.com/dungle-scrubs/aerospace-focus/commit/3cf900998c3ff84f6d81781fb7c4ad981143c51f))
* prevent recursive crash in bar positioning ([600bc45](https://github.com/dungle-scrubs/aerospace-focus/commit/600bc45e63515006c87ae0adc1d1e10dbfe43b03))
* rewrite coordinate conversion, add process timeout, remove force casts ([e11d92b](https://github.com/dungle-scrubs/aerospace-focus/commit/e11d92b7598d887937871352d9ba03da702ba5ea))
* use full path to aerospace binary for launchd compatibility ([060b344](https://github.com/dungle-scrubs/aerospace-focus/commit/060b344ddedc8e9ad4944b4167840fd4bc9892c2))
