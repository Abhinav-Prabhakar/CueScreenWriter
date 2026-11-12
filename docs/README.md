# Cue — marketing site

The static marketing site for **Cue**, a screenwriting app for Mac. It is plain HTML, CSS and
JavaScript: no build step, no package manager, no CDN, and no requests to anywhere but this
folder.

Live at <https://abhinav-prabhakar.github.io/CueScreenWriter/>.

## Run it locally

From this `docs/` folder:

```sh
python3 -m http.server 4173
```

Then open <http://localhost:4173/>. Opening `index.html` directly works for most of the page,
but a local server is better because the demo, fonts and manifest all behave like the deployed
site.

`404.html` uses absolute paths under `/CueScreenWriter/` so it still finds its styles and links
when GitHub Pages serves it for a missing page at any depth. To preview it locally, serve the
site under that same base path:

```sh
# from the repository root
mkdir -p /tmp/cue-pages
ln -sfn "$PWD/docs" /tmp/cue-pages/CueScreenWriter
( cd /tmp/cue-pages && python3 -m http.server 4173 )
```

Then open <http://localhost:4173/CueScreenWriter/> or
<http://localhost:4173/CueScreenWriter/404.html>.

## What is here

```
docs/
├── index.html                     landing page
├── privacy.html                   privacy policy
├── support.html                   support and troubleshooting
├── 404.html                       not-found page
├── README.md                      this file
├── robots.txt                     crawler rules + sitemap
├── sitemap.xml                    the three public pages
├── .nojekyll                      serve files as-is on GitHub Pages
├── preview/                       verification screenshots
└── assets/
    ├── css/site.css               all styling, tokens, layouts and lamp themes
    ├── js/site.js                 lamp, typing, demo editor and page interactions
    ├── fonts/                     Geist and Courier Prime, served locally
    ├── shots/                     app screenshots (daylight, evening, night)
    ├── icons/                     app icon and wordmark
    ├── favicons/                  icon set, web manifest and browser config
    └── og/cue-og.png              1200 × 630 social card
```

## The page

- **Header** — wordmark, four anchors, a compact Download button, and the lamp picker
  (Auto, Daylight, Evening, Night, plus lamp on/off). On phones the anchors move into a
  full-height menu.
- **Hero** — the `FADE IN:` slug, a four-line headline with a typed last line, the promise
  words, and a CSS/SVG MacBook showing the app.
- **Try it** — a working screenplay demo. Type in it: `INT.`/`EXT.` becomes a scene heading,
  an ALL-CAPS line becomes a character, Enter opens the next-line chooser, and Tab cycles the
  element type. It also has a scene-time menu, ghost suggestions, a keyboard-accessible
  element picker, and a reset.
- **Features** — an intro and ten entries, each with its own drawn illustration.
- **Extras** — the nine smaller things, in a grid.
- **Questions** — eight answers in a native `<details>` accordion.
- **Footer** — `FADE OUT.`, “Written, by you.”, the closing note, then Support / Privacy /
  GitHub Releases and the copyright.

Privacy and support use the same header, lamp, footer and 680 px reading measure as the policy
documents they are.

## Design notes

The palette and lamp behaviour come from the app's design tokens. Daylight is clean paper on a
cool desk, Evening warms the paper and lowers the light, and Night puts a dark desk under a lit
page. The choice is stored in `localStorage` under `cue.lamp`; Auto follows the clock
(07:00–17:00 Daylight, 17:00–21:00 Evening, otherwise Night). The lamp can be switched off
with `cue.lit`, which flattens the page to plain paper.

Type is **Geist** for the interface and **Courier Prime** for the screenplay. Both are served
from `assets/fonts/` with `@font-face` and `font-display: swap`. The headline and document
headings use the script face; body copy stays in Geist.

Motion is deliberately quiet: a short reveal on sections, a typing line in the hero, and small
transitions in the demo. Every animation is disabled under `prefers-reduced-motion: reduce`.

## Editing

- **Copy** lives in the HTML. The source of truth for the app's marketing strings is
  `Cue/CueKit/Copy.swift`.
- **Colours, spacing and type** are custom properties at the top of `assets/css/site.css`.
  Lamp variants are the `:root[data-lamp="…"]` blocks directly below.
- **Behaviour** is in `assets/js/site.js`, grouped by feature with a short comment above each
  block. There are no dependencies and no globals beyond the `Cue` namespace.
- **Images** are local. Keep new assets in `assets/` and reference them relatively, so the site
  keeps working from a project subpath.
- **Favicons** can be regenerated from `assets/icons/app-icon-1024.png`; the current set covers
  `.ico`, 16/32 px PNGs, a 180 px Apple touch icon, and 192/512 px standard and maskable icons.

## Deploying

The site is pure static files and is published with GitHub Pages from this folder on the
`main` branch (Settings › Pages › Deploy from a branch: `main` / `/docs`). There is nothing to
build, and no GitHub Actions are used. `.nojekyll` keeps folders such as `assets/` untouched.

`robots.txt`, `sitemap.xml`, the canonical links and the Open Graph URLs all use the project
Pages address. If the site moves to a custom domain, update those places together:
`index.html` (canonical, Open Graph, Twitter, JSON-LD), `privacy.html`, `support.html`,
`404.html` (its absolute asset and page paths), `robots.txt` and `sitemap.xml`.

## Verification

Screenshots in `preview/` were captured with Playwright at:

| File | Viewport | Lamp |
| --- | --- | --- |
| `desktop-daylight.png` | 1440 × 900 | Daylight |
| `desktop-night.png` | 1440 × 900 | Night |
| `mobile.png` | 390 × 844 | Daylight |
| `demo.png` | 1440 × 900, scrolled to the demo | Daylight |

Checked at 1440, 1024, 860, 640 and 390 px: no horizontal overflow, the header collapses
cleanly, the hero headline holds its four lines, the demo remains usable, and the FAQ and lamp
menus work from the keyboard.

## Contact

Support: <https://github.com/Abhinav-Prabhakar/CueScreenWriter/issues> · Downloads:
<https://github.com/Abhinav-Prabhakar/CueScreenWriter/releases>
