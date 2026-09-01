# josuebrunel.github.io

Source for my personal blog, built with [Hugo](https://gohugo.io/) and the [hugo-vitae](https://github.com/dataCobra/hugo-vitae) theme. Live at [josuebrunel.github.io](https://josuebrunel.github.io/).

## Requirements

- [Hugo (extended)](https://gohugo.io/installation/)
- [Dart Sass](https://sass-lang.com/dart-sass/)

## Setup

The theme is included as a git submodule, so clone with submodules:

```sh
git clone --recurse-submodules https://github.com/josuebrunel/josuebrunel.github.io.git
```

If you already cloned without that flag:

```sh
git submodule update --init --recursive
```

## Local development

```sh
make serve
```

Runs the Hugo dev server with drafts enabled. `make help` lists all available targets.

## Build

```sh
make build [BASE_URL=https://example.com/]
make clean
```

`make build` outputs to `docs/` (useful for a manual Pages deploy from the `main` branch). The CI workflow instead builds to `public/` and uploads it as an artifact.

## Deployment

Pushes to `main` are built and deployed automatically to GitHub Pages via `.github/workflows/hugo.yaml`. No manual deploy step needed.

## Content conventions

See [`CLAUDE.md`](./CLAUDE.md) for front matter, tagging, and voice conventions used across posts.
