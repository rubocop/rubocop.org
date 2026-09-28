# RuboCop Landing Page

The landing page for [rubocop.org](https://rubocop.org), built with [Bridgetown](https://www.bridgetownrb.com/), [Tailwind CSS](https://tailwindcss.com/) and [Vite](https://vite.dev/).

## Prerequisites

- [Ruby](https://www.ruby-lang.org/en/downloads/) >= 3.2
- [Node.js](https://nodejs.org) >= 20
- [Bundler](https://bundler.io/)

## Setup

```sh
bundle install && npm install
```

## Development

```sh
bin/bridgetown start
```

Then visit [localhost:4000](http://localhost:4000). This also starts the Vite dev server on port 5173, which serves the frontend assets with hot reloading.

## Linting

```sh
bin/rubocop
```

## Deployment

The site is deployed to GitHub Pages via a [GitHub Actions workflow](.github/workflows/gh-pages.yml). On every push to the `main` branch, the workflow builds the site with `bin/bridgetown deploy` and deploys the `output/` directory.

The workflow automatically sets `BASE_PATH` based on the repository. Forks get `/rubocop.org` so the site works at `<username>.github.io/rubocop.org/`, while the main repo uses `/` for the `rubocop.org` custom domain.

## Plugins

- [bridgetown-svg-inliner](https://github.com/andrewmcodes/bridgetown-svg-inliner): inlines SVG files directly into HTML for styling with CSS

## Data Sources

- **GitHub Releases**: fetched from the GitHub API at build time (`plugins/builders/github_releases.rb`)
- **Site stats** (downloads, stars, cops): configured in `src/_data/site_metadata.yml`
- **Sponsors & Backers**: loaded from Open Collective avatar APIs
