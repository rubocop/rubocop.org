# AGENTS.md

Guidance for AI coding agents working on rubocop.org. The [README](README.md)
explains how the pages are built; this file covers what you need on top of it.

## What this is

The landing site for RuboCop: a home page, an index of every cop (`/cops/`)
and a playground that runs RuboCop in the browser (`/playground/`). It
complements [docs.rubocop.org](https://docs.rubocop.org) rather than repeating
it.

It's built with Bridgetown 2, plain CSS and a few small vanilla JS modules,
bundled by esbuild. There's no Tailwind and no UI framework. Most of what the
pages show comes out of RuboCop itself at build time, so bumping the RuboCop
gems in `Gemfile.lock` changes the site.

## Repo map

| Path | What lives there |
|------|------------------|
| `bin/` | the Bridgetown and RuboCop binstubs, and the checks on a built site (`check-pages.js`) |
| `src/` | the pages (`index.erb`, `cops.erb`, `playground.erb`, `404.erb`), partials and the layout |
| `src/_data/` | hand-kept data: the team, the history log, the plugin list, site metadata |
| `plugins/builders/` | build-time data: the cop registry, the demo runs, the How it works walkthrough, the editor's language server session, GitHub releases, Meta Redux posts, Open Collective backers, the playground's gem archive, template helpers |
| `plugins/rubocop_html.rb` | turns RuboCop's terminal output into HTML, at build time and inside the playground |
| `demo/` | the small project whose RuboCop runs fill the home page terminals |
| `frontend/styles/` | `tokens.css` holds every color for both themes; the rest is a file per page |
| `frontend/javascript/site/` | tabs, the cop grid, the cop index filter, the theme switch, the header progress |
| `frontend/javascript/playground/` | the playground page, its ruby.wasm worker, `prelude.rb` (the Ruby side) and share links |
| `spec/` | builders, helpers, the HTML renderer, the playground's config handling, color contrast |

## Commands

```sh
bin/bridgetown start                       # dev server on localhost:4000 with live reload
npm run esbuild && bin/bridgetown build    # one-off development build into output/
BRIDGETOWN_ENV=production BASE_PATH=/ bin/bridgetown deploy  # what CI deploys
bundle exec rspec
bin/rubocop
yamllint -s .
codespell
bin/check-pages.js                         # on a production build: every page in headless Chrome
```

## Gotchas

- **Check asset paths with `BASE_PATH=/`.** The live site builds with it and
  local builds don't. A trailing slash once turned every asset URL into a
  protocol-relative one (`//_bridgetown/...`) on the live site only. Forks
  deploy under `/rubocop.org`, so links in templates go through
  `relative_url` and `asset_path`.
- **`demo/` is content.** It offends on purpose, and changing a file there
  changes the home page. Keep `SuggestExtensions: false` in its config, or the
  plugins in the site's bundle print a notice into the hero terminal.
- **Production builds need the network.** A failed GitHub fetch fails the
  deploy, so the old site stays up rather than going out without releases.
  Meta Redux and Open Collective are optional, and their sections just
  disappear. In development every fetch is optional and cached for an hour.
  Set `GITHUB_TOKEN` if you hit GitHub's anonymous rate limit.
- **Playground input stays data.** The page hands the code and the config to
  the worker as files under `/pg`. Never interpolate them into Ruby source that
  goes through `vm.eval`.
- **`plugins/rubocop_html.rb` runs in two places**, the Bridgetown build and
  ruby.wasm, so it sticks to the standard library.
- **Some code works around RuboCop and its dependencies**: the Socket stub in
  `prelude.rb` and `UNVERSIONED_DOCS`. Each has a comment saying why. Drop
  one only when the bundled gems no longer need it. `spec/playground_spec.rb`
  fails while some cop still needs the Socket stub.
- **Colors only come from tokens.** Each is a custom property in `tokens.css`
  with a light and a dark value, and `spec/tokens_spec.rb` fails any text color
  under 4.5:1 contrast.
- **Keep the keyboard working.** Tab strips go through `setupTabKeys` (arrow
  keys, Home and End, a roving tabindex), and the cop grid is a single tab
  stop. Try new interactive parts with the keyboard alone.
- **`.rubocop.yml` merges `Exclude` with RuboCop's defaults.** Without that,
  CI lints the gems it installs into `vendor/bundle` and fails.

## Design

The site should look like RuboCop's own habitat: terminal output, offense
messages, Ruby comments, YAML, a git log. Reach for those before the usual
landing page parts (gradients, feature cards, icon grids, testimonials). When
a page shows RuboCop doing something, it should come from a real run at build
time, not a mockup.

Copy is short and plain, in the maintainer's voice, with no marketing
superlatives.

## Conventions

- Every behavior change gets a spec.
- Focused commits that explain the why. Reference issues with `[#NN]`, and use
  `[Fix #NN]` only when the commit closes the issue.
- Linear history: rebase or fast-forward, and rebase-merge PRs.
- No `--` or em-dashes in prose: Markdown, comments and page copy.
- No AI attribution in commits, PRs or comments: no `Co-Authored-By` trailers
  naming an AI tool, no "Generated with" footers.
- Don't post to GitHub (issues, PRs, comments) without being asked.
