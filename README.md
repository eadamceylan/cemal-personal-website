# Cemal Ceylan — Personal Website

A modern single-page personal portfolio featuring basketball, taekwondo, interests, background, and contact information.

## View locally

Open `index.html` in a web browser. No build step or dependencies are required.

## Project files

- `index.html` — page content and structure
- `style.css` — responsive layout and styling
- `assets/` — the two optimized images used by the website

## Responsive check

On Windows with Chrome and Python installed, run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\test-mobile-layout.ps1
```

The check verifies layout bounds across 320px, 375px, 768px, 1024px, and 1440px viewports, including mobile subject framing for both full-screen photos.

