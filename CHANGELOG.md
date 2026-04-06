# Changelog

## [0.1.5](https://github.com/cpoepke/obsidian-docker/compare/v0.1.4...v0.1.5) (2026-04-06)


### Features

* add on-demand git pull server and periodic pull interval ([#7](https://github.com/cpoepke/obsidian-docker/issues/7)) ([aeee558](https://github.com/cpoepke/obsidian-docker/commit/aeee5584c90432b91985784190724dc250b2ab61))


### Bug Fixes

* check for main.js before skipping plugin copy ([126f329](https://github.com/cpoepke/obsidian-docker/commit/126f32912754d676bfc80f84b2bbb942d6c8fb81))
* install plugins to /opt/obsidian-plugins to survive PVC mounts ([760e556](https://github.com/cpoepke/obsidian-docker/commit/760e556087b9dc7f5341b982524dd187e7618acb))

## [0.1.4](https://github.com/cpoepke/obsidian-docker/compare/v0.1.3...v0.1.4) (2026-04-05)


### Features

* push versioned Docker images on release via release-please workflow ([18ab1d3](https://github.com/cpoepke/obsidian-docker/commit/18ab1d33d855c9505f8ec1ee6ae5fe046f4cdcae))

## [0.1.3](https://github.com/cpoepke/obsidian-docker/compare/v0.1.2...v0.1.3) (2026-04-05)


### Bug Fixes

* trigger versioned Docker image push on release events ([15389f1](https://github.com/cpoepke/obsidian-docker/commit/15389f1cfac0d16f01a212453c0deefdfc6e19f9))

## [0.1.2](https://github.com/cpoepke/obsidian-docker/compare/v0.1.1...v0.1.2) (2026-04-05)


### Features

* add HEALTHCHECK to Dockerfile for standalone docker run ([afb34a1](https://github.com/cpoepke/obsidian-docker/commit/afb34a194707a8930c5b23ac59d88b18652308cf))


### Bug Fixes

* add semver Docker image tags and trigger on version tags ([abba5cd](https://github.com/cpoepke/obsidian-docker/commit/abba5cde69461186e4ab51fb87c81faecd791d3e))

## [0.1.1](https://github.com/cpoepke/obsidian-docker/compare/v0.1.0...v0.1.1) (2026-04-05)


### Bug Fixes

* configure release-please manifest starting at 0.1.0 ([fbb9000](https://github.com/cpoepke/obsidian-docker/commit/fbb9000cbe6a71b09d974cb32d8de0a74688db27))
