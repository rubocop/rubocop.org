# RuboCop Landing Page

The landing page for [rubocop.org](https://rubocop.org), built with [Bridgetown](https://www.bridgetownrb.com/) and plain CSS.

The site is meant to complement the [docs](https://docs.rubocop.org), not repeat them: a front page, an index of every cop, and a playground that runs RuboCop in the browser.

## Prerequisites

- [Ruby](https://www.ruby-lang.org/en/downloads/) >= 3.2
- [Node.js](https://nodejs.org) >= 22
- [Google Chrome](https://www.google.com/chrome/), for the page checks
- [Bundler](https://bundler.io/)

## Setup

```sh
bundle install && npm install
```

## Development

```sh
bin/bridgetown start
```

Then visit [localhost:4000](http://localhost:4000).

## Linting and specs

```sh
bin/rubocop
bundle exec rspec
```

Then there are checks on a production build (a development build adds live reload, which the page checks count as an error):

```sh
BRIDGETOWN_ENV=production BASE_PATH=/ bin/bridgetown deploy
bin/check-pages.js   # every page in headless Chrome, the playground included
bin/check-links      # the links into the docs, the style guide, GitHub and Meta Redux
```

## How the pages are built

Most of what the site shows comes from RuboCop itself, at build time:

- **The cop index** (`/cops/`) and the grid on the home page come from the cop registry of RuboCop and its official plugins, loaded from this site's bundle (`plugins/builders/cops.rb`).
- **The terminal output** on the home page is RuboCop run on the small project in `demo/` (`plugins/builders/demo_runs.rb`). Change the files there and the examples follow. How it works follows the offense in `demo/lib/user.rb`, and `plugins/builders/walkthrough.rb` adds its tree and the pattern that matches it. The editor pane is a `rubocop --lsp` session on `demo/lib/greeter.rb` (`plugins/builders/editor.rb`).
- **The try links** on the cop index open the first example from a cop's docs in the playground, with only that cop turned on (`plugins/builders/examples.rb`). An example the cop finds nothing in gets no link.
- **The playground** (`/playground/`) runs RuboCop on [ruby.wasm](https://github.com/ruby/ruby.wasm) in a web worker. The Ruby runtime is loaded from jsDelivr, and the build packs the RuboCop from this bundle, with its dependencies, into an archive next to the page (`plugins/builders/playground.rb`). The worker and the Ruby side of it live in `frontend/javascript/playground/`.
- **News** combines the latest GitHub releases (`plugins/builders/github.rb`) with the RuboCop posts on [Meta Redux](https://metaredux.com) (`plugins/builders/news.rb`).
- **The backers** in the funding section come from the project's [Open Collective](https://opencollective.com/rubocop) members list (`plugins/builders/open_collective.rb`).

`plugins/rubocop_html.rb` turns RuboCop's terminal output into HTML wherever the site shows it.

So a new RuboCop release reaches the site by bumping the gems in `Gemfile.lock`. Dependabot opens the update, and [a workflow](.github/workflows/merge-rubocop-updates.yml) merges it once its checks pass. A major release waits for someone to look at it.

The core team, the history log and the plugin list are plain data in `src/_data/`.

The fonts are Martian Grotesk and Martian Mono by Evil Martians, under the SIL Open Font License (see `frontend/fonts/`).

## Deployment

The site is deployed to GitHub Pages via a [GitHub Actions workflow](.github/workflows/gh-pages.yml). It builds the site with `bin/bridgetown deploy`, runs the page checks on it and deploys the `output/` directory on every push to `main` and once a day, to pick up new releases and posts. The link check runs next to the deploy rather than before it, so a broken link doesn't hold the site back.

The workflow automatically sets `BASE_PATH` based on the repository. Forks get `/rubocop.org` so the site works at `<username>.github.io/rubocop.org/`, while the main repo uses `/` for the `rubocop.org` custom domain.
