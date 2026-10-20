# ReconDork

A bug bounty Google dork generator. Point it at a domain and it builds a clean light/dark HTML report of 131 ready-to-run Google searches — covering secrets, config files, directory listings, sensitive documents, admin panels, API surfaces, cloud and third-party leaks, and code and paste sites. Click any dork to run the search, or copy it with one tap. A fast, quiet first step for the recon phase of authorized bug bounty and pentest work.

## Usage

```bash
chmod +x ReconDork.sh

./ReconDork.sh example.com        # search the domain (site:example.com)
./ReconDork.sh -w example.com     # wildcard: search the subdomains (site:*.example.com)
./ReconDork.sh                    # show the help
```

The report is saved in the current directory as `recondork_<domain>_<mode>_<timestamp>.html` and opened in your browser (WSL, macOS and Linux are supported). On a machine without a browser, the script prints the file path instead.

You can pass a full URL — `https://www.example.com/login?x=1` is cleaned up to `example.com`. Internationalized domains must be given in punycode (e.g. `idn2 münchen.de` → `xn--mnchen-3ya.de`).

## What it covers

| Area | Sections | Dorks |
|---|---|---|
| Recon & exposure | Subdomain discovery, version control exposure, directory listing, recently indexed pages | 12 |
| Secrets & config | Secrets & tokens, environment & config files, Docker & dependency files | 18 |
| Parameters by bug class | XSS, SQL injection, LFI / path traversal, SSRF, RCE, open redirect, IDOR, tokens in URLs | 19 |
| Files & data | Confidential documents, data dumps & PII, logs, backups, file extensions | 23 |
| Panels & endpoints | Admin & login panels, signup / reset flows, upload endpoints, tech endpoints, GraphQL, API docs, SSO / identity config, server status | 22 |
| Errors & platforms | Errors & debug pages, WordPress leaks | 10 |
| Off-site leaks | Cloud storage, third-party SaaS, shared docs, code & paste sites | 27 |

The XSS, LFI and open-redirect sections include the full "Top 25" parameter lists.

Every dork follows Google's search rules: only supported operators, at most 32 words per query, only file types Google can index, and very short parameter names (`q=`, `s=`, `id=` …) kept in their own dork so they don't flood the others with results.

## The report

- **Category chips** and a **filter box** (press `/` to focus, `Esc` to clear) to find dorks quickly.
- **Colour-coded syntax** for operators, quoted text and `OR`.
- **Progress tracking** — tick a dork (or just open it) and the progress ring updates; ticks are remembered per target in your browser.
- **One-click copy** of any dork.
- **Light and dark themes** that follow your system setting, with a toggle.
- Links open Google with `filter=0`, so results Google would hide as "similar" are shown.

## Requirements

- bash 4 or newer (on macOS: `brew install bash`)
- A web browser to view the report

## Notes

- Space out your searches — opening many dorks in quick succession can trigger Google CAPTCHAs.
- An empty result is normal for a well-secured target; it means nothing was found, not that the dork is broken.
- `-w` mode uses `site:*.example.com`, which works on Google but is not officially supported. `site:example.com` already includes subdomains.
- Only run these searches against assets you are authorized to test.

## Workflow

![ReconDork report (light theme)](docs/screenshot-1.png)
![ReconDork report filtered for "api", with opened dorks ticked (dark theme)](docs/screenshot-2.png)
