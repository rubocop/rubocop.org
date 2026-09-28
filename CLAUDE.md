# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The single-page marketing/landing site for rubocop.org, built with Bridgetown 2 (Ruby static site generator, ERB templates) and Tailwind CSS v4 bundled via esbuild. There are no tests; "correctness" is a clean build plus lint.

## Commands

Ruby and Node versions are pinned in `.ruby-version` / `.node-version` and managed by mise (`mise.toml` enables idiomatic version files). The README's "Ruby >= 3.2 / Node >= 20" is outdated. RuboCop targets Ruby 4.0, so modern syntax (e.g. `it` block params) is fine.

```sh
bundle install && npm install      # setup
bin/bridgetown start               # dev server on localhost:4000 (Bridgetown + esbuild watch)
bin/bridgetown deploy              # production build into output/ (what CI runs)
bin/rubocop                        # Ruby lint (CI: bundle exec rubocop)
bin/rubocop -a                     # autocorrect
yamllint .                         # YAML lint, strict mode in CI
codespell                          # spell check (config in .codespellrc), runs on PRs
```

`config/initializers.rb` is not reloaded by the dev server; restart after changing it. New Tailwind classes in ERB may also need a restart to show up.

## Architecture

- **Page content** lives almost entirely in `src/index.erb`, wrapped by `src/_layouts/default.erb`, which pulls in `src/_partials/_head.erb`, `_footer.erb`, and the `Shared::Navbar` component (`src/_components/shared/navbar.{rb,erb}`, a `Bridgetown::Component`).
- **Site data**: `src/_data/site_metadata.yml` holds titles, external URLs, and the hand-maintained stats (downloads, stars, cop count). Templates read it as `site.metadata.*`.
- **Build-time data fetch**: `plugins/builders/github_releases.rb` hits the GitHub Releases API on `:post_read` and puts the latest 3 releases into `site.data[:latest_releases]`. On failure it logs a warning and returns `[]`, and the template hides the releases section. Builders subclass `SiteBuilder` (`plugins/site_builder.rb`) and are auto-loaded from `plugins/builders/`.
- **Tailwind JIT refresh**: `plugins/builders/tailwind_jit.rb` rewrites `frontend/styles/jit-refresh.css` after a fast refresh so esbuild recompiles CSS. That file is imported by `frontend/styles/index.css` purely as a rebuild trigger.
- **Frontend**: `frontend/javascript/index.js` is the esbuild entry point: plain vanilla JS for copy-to-clipboard (`.copy-btn` + `data-copy`), the Before/After code tabs (`#code-before` / `#code-after`), and the mobile nav toggle. `frontend/styles/index.css` defines the Tailwind `@theme` tokens (`accent`, `heading`, `muted`, `code-bg`, fonts) and the custom `.code-example` / `.code-tab` styles. Tailwind scans `src/` via `@source "../../src"`.
- **Icons**: SVGs in `src/images/` are inlined with the `svg` helper from `bridgetown-svg-inliner` (`<%= svg "images/foo.svg", class: "..." %>`) so they can be styled with `currentColor`.

## Base path / deployment

The site deploys to GitHub Pages on every push to `main` (`.github/workflows/gh-pages.yml`). `BASE_PATH` is `/` for `rubocop/rubocop.org` and `/rubocop.org` for forks. It's consumed by both `config/initializers.rb` (`base_path`) and `esbuild.config.js` (`publicPath`). Internal links and assets therefore must go through `relative_url` / `asset_path`, never hard-coded absolute paths.
