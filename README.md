# ReconDork

A bug bounty Google dork generator. Point it at a domain and it builds a clean light/dark HTML report of 131 ready-to-run Google searches — covering secrets, config files, directory listings, sensitive documents, admin panels, API surfaces, cloud and third-party leaks, and code and paste sites. Click any dork to run the search, or copy it with one tap. A fast, quiet first step for the recon phase of authorized bug bounty and pentest work.

## Usage

```bash
chmod +x ReconDork.sh

./ReconDork.sh example.com        # search the domain (site:example.com)
./ReconDork.sh -w example.com     # wildcard: search the subdomains (site:*.example.com)
```

## Workflow

![ReconDork report (light theme)](docs/screenshot-1.png)
![ReconDork report filtered for "api", with opened dorks ticked (dark theme)](docs/screenshot-2.png)
