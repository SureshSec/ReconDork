#!/usr/bin/env bash
#
# ReconDork.sh - Bug bounty Google dork generator
#
# Builds clickable Google-search links for a target domain, writes a timestamped
# light/dark-themed HTML report in the current directory, then opens it.
#
if [[ -z "${BASH_VERSINFO[0]:-}" ]] || (( BASH_VERSINFO[0] < 4 )); then
  echo "Error: ReconDork.sh requires bash >= 4 (found ${BASH_VERSION:-unknown}). On macOS: brew install bash" >&2
  exit 1
fi
set -euo pipefail
# Treat '&' in ${var//pat/repl} replacements as a literal, not the matched text
# (bash 5.2+ patsub_replacement); keeps htmlesc and placeholder substitution safe.
shopt -u patsub_replacement 2>/dev/null || true

usage() {
  local code="${1:-0}" msg
  msg="$(cat <<'U'
ReconDork.sh - Bug bounty Google dork generator

Usage:
  ./ReconDork.sh example.com             # Search the domain (site:example.com).
  ./ReconDork.sh -w example.com          # Wildcard: search the subdomains (site:*.example.com).
U
)"
  if (( code )); then printf '%s\n' "$msg" >&2; else printf '%s\n' "$msg"; fi
  exit "$code"
}

# ---------------------------------------------------------------------------
# 1. Parse arguments
# ---------------------------------------------------------------------------
WILD=0; domain=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--wild)     WILD=1 ;;
    -h|--help)     usage 0 ;;
    -*)            echo "Unknown option: $1" >&2; usage 1 ;;
    *)
      if [[ -n "$domain" ]]; then
        echo "Error: only one target domain allowed (got '$domain' and '$1')." >&2; usage 1
      fi
      domain="$1" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# 2. Get + normalize + strictly validate the domain
# ---------------------------------------------------------------------------
if [[ -z "$domain" ]]; then
  usage 0                     # no target given: show the help
fi

domain="${domain//[[:space:]]/}"   # tolerate accidental whitespace
domain="${domain,,}"          # lowercase
if [[ "$domain" =~ ^[a-z][a-z0-9+.-]*:// ]]; then
  domain="${domain#*://}"     # strip scheme (only when it leads the string)
fi
domain="${domain%%/*}"        # strip /path
domain="${domain%%\?*}"       # strip ?query
domain="${domain%%#*}"        # strip #fragment
domain="${domain##*@}"        # strip user:pass@ (after path/query, which may contain '@')
domain="${domain%%:*}"        # strip :port
domain="${domain#\*.}"        # strip leading *.
domain="${domain#www.}"       # strip leading www.
domain="${domain%.}"          # strip trailing dot

hostname_re='^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,63}|xn--[a-z0-9-]{0,58}[a-z0-9])$'
is_hostname() {   # match under LC_ALL=C: in UTF-8 locales [a-z] can also match letters like 'ü'
  local LC_ALL=C
  [[ "$1" =~ $hostname_re ]]
}
if (( ${#domain} > 253 )) || ! is_hostname "$domain"; then   # 253 = DNS name limit
  echo "Invalid domain: '$domain'" >&2
  echo "Expected something like: example.com, sub.example.co.uk, or an xn-- IDN host." >&2
  echo "Unicode names must be converted to punycode first (e.g. 'idn2 münchen.de' -> xn--mnchen-3ya.de)." >&2
  exit 1
fi

# @SITE@  = target used as a site: operator (flag-controlled).
# @DOM@   = bare domain as a quoted search string (never wildcarded).
# @SINCE@ = start of last year, for after: (recently indexed) dorks.
# @NEG@   = '-site:www.<domain>' in wildcard mode, empty in domain mode.
if [[ "$WILD" == 1 ]]; then
  SITE="*.$domain"; MODE="WILDCARD SEARCH (site:*.$domain — subdomains)"
  NEG="-site:www.$domain"
else
  SITE="$domain";   MODE="DOMAIN SEARCH (site:$domain)"
  NEG=""
fi
SINCE="$(( $(date +%Y) - 1 ))-01-01"

echo "[*] Target : $domain"
echo "[*] Mode   : $MODE"
if [[ "$WILD" == 0 ]]; then
  echo "[i] Use -w/--wild for a wildcard (*.$domain) subdomain search."
fi
echo "[!] SCOPE  : only run these against assets you are authorized to test."

# ---------------------------------------------------------------------------
# 3. Helpers
# ---------------------------------------------------------------------------
urlencode() {   # UTF-8-safe percent-encoding (per-byte under LC_ALL=C)
  local LC_ALL=C
  local s="$1" out="" i c
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) printf -v c '%%%02X' "'$c"; out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

htmlesc() {     # pure-bash (no subprocess); '&' must be escaped first
  local s="$1" q="'"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//$q/&#39;}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# 4. Dork list. Lines starting with '#' are category headers.
#    Placeholders: @SITE@ (flag-controlled), @DOM@ (bare), @SINCE@ (after: date),
#    @NEG@ (wildcard-only www exclusion).
# ---------------------------------------------------------------------------
read -r -d '' DORKS <<'EOF' || true
# Subdomain discovery
site:@SITE@ -site:www.@DOM@
site:@SITE@ (inurl:dev OR inurl:staging OR inurl:test OR inurl:uat OR inurl:qa OR inurl:beta OR inurl:sandbox OR inurl:preprod) @NEG@
site:@SITE@ (inurl:internal OR inurl:corp OR inurl:intranet OR inurl:vpn OR inurl:portal OR inurl:gateway OR inurl:admin OR inurl:staff) @NEG@
site:@SITE@ (inurl:jenkins OR inurl:gitlab OR inurl:jira OR inurl:confluence OR inurl:grafana OR inurl:kibana OR inurl:api) @NEG@
# Secrets & tokens
site:@SITE@ ("private_key_id" ("client_email" OR "service_account"))
site:@SITE@ ("DB_PASSWORD" OR "DATABASE_URL" OR "client_secret")
site:@SITE@ ("AWS_ACCESS_KEY_ID" OR "AWS_SECRET_ACCESS_KEY")
site:@SITE@ ("api_key" OR "apikey" OR "secret_key" OR "access_token" OR "private_key")
site:@SITE@ ("jdbc:mysql" OR "jdbc:postgresql" OR "jdbc:sqlserver" OR "jdbc:oracle" OR "mongodb+srv")
site:@SITE@ ("Authorization: Bearer" OR "Authorization: token")
site:@SITE@ (ext:pem OR ext:key OR ext:ppk)
site:@SITE@ ("sk_live_" OR "pk_live_")
site:@SITE@ ext:js ("apiKey" OR "api_key" OR "secret")
site:@SITE@ ("BEGIN PRIVATE KEY" OR "BEGIN RSA PRIVATE KEY" OR "BEGIN OPENSSH PRIVATE KEY" OR "BEGIN EC PRIVATE KEY")
# Environment & config files
site:@SITE@ (inurl:.env OR ext:env)
site:@SITE@ (inurl:wp-config.php.bak OR inurl:wp-config.bak OR inurl:config.php.bak OR inurl:web.config.bak OR inurl:settings.py.bak)
site:@SITE@ (inurl:credentials OR inurl:sftp-config.json OR inurl:config.json)
site:@SITE@ ("APP_KEY" OR "APP_ENV" OR "JWT_SECRET" OR "REDIS_PASSWORD" OR "MAIL_PASSWORD")
site:@SITE@ "connectionString" (ext:config OR ext:xml OR ext:txt)
site:@SITE@ "password" (ext:properties OR ext:conf OR ext:ini OR ext:cfg OR ext:bak OR ext:old)
# Docker & dependency files
site:@SITE@ (ext:tfstate OR ext:tfvars OR inurl:docker-compose.yml OR inurl:Dockerfile)
site:@SITE@ (inurl:composer.json OR inurl:composer.lock OR inurl:package.json OR inurl:package-lock.json OR inurl:requirements.txt)
# Version control exposure
site:@SITE@ (inurl:.git OR inurl:.svn)
# Top params — XSS
site:@SITE@ (inurl:search= OR inurl:lang= OR inurl:keyword= OR inurl:query= OR inurl:page= OR inurl:keywords= OR inurl:year= OR inurl:view= OR inurl:email=)
site:@SITE@ (inurl:type= OR inurl:name= OR inurl:month= OR inurl:image= OR inurl:list_type= OR inurl:url= OR inurl:terms= OR inurl:categoryid= OR inurl:key=)
site:@SITE@ (inurl:begindate= OR inurl:enddate= OR inurl:searchterm= OR inurl:message= OR inurl:comment= OR inurl:callback= OR inurl:jsonp= OR inurl:title= OR inurl:description= OR inurl:msg=)
site:@SITE@ (inurl:q= OR inurl:s= OR inurl:id= OR inurl:p= OR inurl:l=)
# Top params — SQL Injection
site:@SITE@ (inurl:id= OR inurl:category= OR inurl:categoryid= OR inurl:catid= OR inurl:productid= OR inurl:userid= OR inurl:groupid= OR inurl:item= OR inurl:report= OR inurl:order= OR inurl:sort= OR inurl:select=)
site:@SITE@ (inurl:pid= OR inurl:uid= OR inurl:cat= OR inurl:product= OR inurl:page_id=)
# Top params — LFI / Path Traversal
site:@SITE@ (inurl:cat= OR inurl:dir= OR inurl:action= OR inurl:board= OR inurl:date= OR inurl:detail= OR inurl:file= OR inurl:download= OR inurl:path= OR inurl:folder= OR inurl:prefix= OR inurl:include=)
site:@SITE@ (inurl:page= OR inurl:inc= OR inurl:locate= OR inurl:show= OR inurl:doc= OR inurl:site= OR inurl:type= OR inurl:view= OR inurl:content= OR inurl:document= OR inurl:layout= OR inurl:mod=)
site:@SITE@ (inurl:conf= OR inurl:filepath= OR inurl:file_path= OR inurl:filename= OR inurl:file_name= OR inurl:pathname= OR inurl:directory= OR inurl:template= OR inurl:attachment= OR inurl:rootpath= OR inurl:require= OR inurl:retrieve=)
# Top params — SSRF
site:@SITE@ (inurl:url= OR inurl:uri= OR inurl:proxy= OR inurl:fetch= OR inurl:remote= OR inurl:endpoint= OR inurl:image_url= OR inurl:link_url= OR inurl:host= OR inurl:domain= OR inurl:feed= OR inurl:server=)
site:@SITE@ (inurl:"url=http" OR inurl:src= OR inurl:dest=)
# Top params — RCE
site:@SITE@ (inurl:cmd= OR inurl:exec= OR inurl:command= OR inurl:execute= OR inurl:ping= OR inurl:shell= OR inurl:eval= OR inurl:payload= OR inurl:function= OR inurl:process= OR inurl:run= OR inurl:system=)
site:@SITE@ inurl:daemon=
site:@SITE@ inurl:ip=
# Top params — Open Redirect
site:@SITE@ (inurl:next= OR inurl:url= OR inurl:target= OR inurl:rurl= OR inurl:dest= OR inurl:destination= OR inurl:redir= OR inurl:redirect_uri= OR inurl:redirect_url= OR inurl:redirect= OR inurl:view= OR inurl:image_url=)
site:@SITE@ (inurl:return= OR inurl:returnTo= OR inurl:return_to= OR inurl:checkout_url= OR inurl:continue= OR inurl:return_path= OR inurl:redirect_to= OR inurl:returnurl= OR inurl:return_url= OR inurl:goto= OR inurl:forward= OR inurl:referer=)
site:@SITE@ (inurl:go= OR inurl:redirect.cgi OR inurl:out OR inurl:"login?to=")
# Top params — IDOR
site:@SITE@ (inurl:user_id= OR inurl:account= OR inurl:invoice= OR inurl:profile= OR inurl:doc_id=)
# Tokens & sensitive data in URLs
site:@SITE@ (inurl:token= OR inurl:access_token= OR inurl:api_key= OR inurl:apikey= OR inurl:session= OR inurl:sid= OR inurl:auth= OR inurl:jwt= OR inurl:phone=)
# Confidential & internal documents
site:@SITE@ ("confidential" OR "not for distribution" OR "not for public release" OR "restricted" OR "proprietary" OR "do not distribute") (ext:pdf OR ext:doc OR ext:docx)
site:@SITE@ "for internal use only" (ext:pdf OR ext:doc OR ext:docx OR ext:xls OR ext:xlsx OR ext:ppt OR ext:pptx)
site:@SITE@ ("192.168" OR "10.0.0" OR "172.16" OR "172.31") (ext:pdf OR ext:txt OR ext:log OR ext:xls OR ext:xlsx)
site:@SITE@ ("intranet.@DOM@" OR "internal.@DOM@" OR "vpn.@DOM@" OR "corp.@DOM@") (ext:pdf OR ext:doc OR ext:docx OR ext:xlsx OR ext:txt)
site:@SITE@ ("password" OR "credentials") (ext:xls OR ext:xlsx OR ext:doc OR ext:docx OR ext:pdf OR ext:txt)
site:@SITE@ ("username" "password") (ext:xls OR ext:xlsx OR ext:csv OR ext:txt)
# Data dumps & PII
site:@SITE@ (ext:xls OR ext:xlsx OR ext:csv) ("email" OR "phone" OR "ssn" OR "salary" OR "dob")
site:@SITE@ (ext:csv OR ext:xlsx) ("customer" OR "employee" OR "contact list")
site:@SITE@ (ext:csv OR ext:txt) "@gmail.com"
site:@SITE@ "@@DOM@" (ext:csv OR ext:xls OR ext:xlsx OR ext:txt)
# Application & database logs
site:@SITE@ (inurl:debug.log OR inurl:error.log OR inurl:error_log OR inurl:access.log OR inurl:access_log OR inurl:application.log OR inurl:laravel.log OR inurl:logs)
site:@SITE@ ext:log ("error" OR "exception" OR "password" OR "username")
site:@SITE@ (inurl:database.sql OR inurl:backup.sql OR inurl:dump.sql)
site:@SITE@ ext:sql ("MySQL dump" OR "INSERT INTO")
site:@SITE@ (inurl:db_backup OR inurl:dbdump OR inurl:database)
# File-upload & import endpoints
site:@SITE@ (inurl:upload OR inurl:uploads OR inurl:uploader OR inurl:fileupload OR inurl:import OR "choose file")
# Backup & source & temp & archive files
site:@SITE@ (inurl:.php.bak OR inurl:.php.old OR inurl:.php.save OR inurl:.php.txt)
site:@SITE@ (ext:inc OR ext:tpl OR ext:phps OR inurl:.asp.bak)
site:@SITE@ (inurl:backup OR inurl:backups OR inurl:old OR inurl:bak)
# Files & extensions
site:@SITE@ (ext:log OR ext:txt OR ext:conf OR ext:cnf OR ext:ini OR ext:bak OR ext:backup OR ext:old OR ext:json)
site:@SITE@ (ext:yml OR ext:yaml OR ext:toml OR ext:xml OR ext:properties OR ext:config OR ext:cfg OR ext:reg OR ext:rdp)
site:@SITE@ (ext:sh OR ext:bash OR ext:ps1 OR ext:bat)
site:@SITE@ (ext:sql OR ext:dump)
site:@SITE@ (filetype:xls OR filetype:xlsx OR filetype:csv OR filetype:pdf OR filetype:doc OR filetype:docx OR filetype:ppt OR filetype:pptx)
# Directory listing
site:@SITE@ intitle:"index of"
site:@SITE@ intitle:"index of" "parent directory"
site:@SITE@ intitle:"index of" ("backup" OR ".git" OR ".env" OR "config" OR "uploads" OR "files")
site:@SITE@ intitle:"index of" ("zip" OR "tar.gz" OR "sql" OR "bak")
# Admin & auth panels & login
site:@SITE@ (inurl:admin OR inurl:administrator OR inurl:login OR inurl:signin OR inurl:auth OR inurl:dashboard OR inurl:panel OR inurl:cpanel)
site:@SITE@ (intitle:login OR intitle:"sign in" OR inurl:secure OR inurl:portal)
site:@SITE@ (inurl:phpmyadmin OR intitle:"phpMyAdmin")
site:@SITE@ (intitle:"Apache Tomcat" OR inurl:manager/html OR inurl:host-manager)
site:@SITE@ (inurl:jenkins OR intitle:"Dashboard [Jenkins]")
site:@SITE@ (inurl:grafana OR intitle:"Grafana" OR intitle:"Kibana")
site:@SITE@ (inurl:actuator OR intitle:"Whitelabel Error Page")
site:@SITE@ (inurl:solr OR inurl:elasticsearch OR intitle:"Solr Admin")
# Signup & reset & invite flows
site:@SITE@ (inurl:register OR inurl:signup OR inurl:reset OR inurl:forgot OR inurl:password OR inurl:invite OR inurl:activate OR inurl:token=)
# Tech & legacy endpoints
site:@SITE@ (ext:php OR ext:asp OR ext:aspx OR ext:jsp OR ext:do OR ext:action OR ext:cgi)
# GraphQL & extra API surfaces
site:@SITE@ (inurl:graphql OR inurl:graphiql OR inurl:graphql-playground OR inurl:altair)
site:@SITE@ (ext:wsdl OR inurl:wsdl)
site:@SITE@ (inurl:api/v1 OR inurl:api/v2 OR inurl:api/v3 OR inurl:rest)
site:@SITE@ ext:json inurl:api
# API docs & specifications
site:@SITE@ (inurl:swagger OR inurl:swagger-ui OR inurl:api-docs OR inurl:apidocs OR inurl:openapi OR inurl:redoc OR inurl:api-explorer)
site:@SITE@ (intitle:"Swagger UI" OR intitle:"ReDoc" OR intitle:"API Reference")
site:@SITE@ (ext:json OR ext:yaml OR ext:yml) ("swagger" OR "openapi")
# Identity & auth provider config
site:@SITE@ (inurl:saml/metadata OR inurl:adfs/ls OR inurl:protocol/openid-connect OR inurl:auth/realms)
site:@SITE@ (inurl:saml OR inurl:sso OR inurl:oauth OR inurl:.well-known)
# Server status & info pages
site:@SITE@ (inurl:server-status OR inurl:server-info)
site:@SITE@ (inurl:phpinfo OR intitle:"phpinfo()" OR "published by the PHP Group")
# Errors & debug leakage
site:@SITE@ ("stack trace" OR "SQL syntax" OR "Traceback" OR "Fatal error" OR "PHP Warning" OR "database error" OR "undefined index" OR "unhandled exception") (ext:php OR ext:log OR ext:txt)
site:@SITE@ (intitle:"exception" OR intitle:"error" OR inurl:error)
site:@SITE@ ("sql syntax near" OR "mysql_fetch_array" OR "mysql_fetch_assoc" OR "SQLSTATE" OR "ORA-00933" OR "ORA-01756")
site:@SITE@ ext:php "Warning" "on line"
site:@SITE@ ("Whoops! There was an error" OR "Page not found at /" OR "DEBUG = True" OR "Traceback (most recent call last)" OR "Server Error in '/' Application")
site:@SITE@ "Server at" "Port" "Apache"
site:@SITE@ (inurl:debug OR inurl:demo OR inurl:temp)
# WordPress-specific leaks
site:@SITE@ (inurl:wp-admin OR inurl:wp-login OR inurl:wp-json)
site:@SITE@ inurl:wp-content/uploads (ext:sql OR ext:txt OR ext:log)
site:@SITE@ inurl:wp-json/wp/v2/users
# Recently indexed
site:@SITE@ after:@SINCE@
site:@SITE@ (ext:pdf OR ext:doc OR ext:docx OR ext:xls OR ext:xlsx OR ext:csv OR ext:txt) after:@SINCE@
site:@SITE@ (inurl:admin OR inurl:login OR inurl:api OR inurl:dev OR inurl:staging) after:@SINCE@
# Cloud storage
site:s3.amazonaws.com "@DOM@"
site:amazonaws.com "@DOM@"
site:storage.googleapis.com "@DOM@"
site:googleusercontent.com "@DOM@"
site:firebasestorage.googleapis.com "@DOM@"
site:blob.core.windows.net "@DOM@"
site:azurewebsites.net "@DOM@"
site:dev.azure.com "@DOM@"
site:digitaloceanspaces.com "@DOM@"
site:r2.dev "@DOM@"
# Third-party SaaS
site:zendesk.com "@DOM@"
site:freshdesk.com "@DOM@"
site:herokuapp.com "@DOM@"
site:sharepoint.com "@DOM@"
site:box.com "@DOM@"
# Shared docs
site:docs.google.com "@DOM@"
site:drive.google.com "@DOM@"
site:dropbox.com/s "@DOM@"
# Code & paste sites
site:github.com "@DOM@"
site:github.com "@DOM@" ("password" OR "api_key" OR "secret" OR "token")
site:gist.github.com "@DOM@"
site:gitlab.com "@DOM@"
site:bitbucket.org "@DOM@"
site:pastebin.com "@DOM@"
site:trello.com "@DOM@"
site:postman.com "@DOM@"
site:atlassian.net "@DOM@"
EOF

# ---------------------------------------------------------------------------
# 5. Output path: current directory (timestamp + PID so re-runs never clobber earlier reports)
# ---------------------------------------------------------------------------
if [[ ! -w . ]]; then
  echo "Error: the current directory is not writable: $PWD" >&2; exit 1
fi
ts="$(date +%Y%m%d-%H%M%S)-$$"
if [[ "$WILD" == 1 ]]; then tag="wild"; else tag="domain"; fi
fname_dom="${domain:0:100}"   # keep file names under the 255-byte limit for very long domains
out="$PWD/recondork_${fname_dom}_${tag}_${ts}.html"
GB="https://www.google.com/search?q="
GB_TAIL="&amp;filter=0"   # show results Google would otherwise hide as "similar" (HTML-escaped &)
dom_esc="$(htmlesc "$domain")"
if [[ "$WILD" == 1 ]]; then mode_esc="Wildcard · site:$(htmlesc "$SITE")"; else mode_esc="Domain · site:$dom_esc"; fi
gen_esc="$(date '+%Y-%m-%d %H:%M')"

# ---------------------------------------------------------------------------
# 6. Emit HTML, de-duplicated
# ---------------------------------------------------------------------------
declare -A seen=()
total=0; dupes=0

{
cat <<HTMLHEAD
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>ReconDork · ${dom_esc}</title>
<style>
  :root{
    --bg:#faf7f2; --surface:#ffffff; --hero:#f3ece1; --fg:#2a251f; --muted:#7a7064; --border:#e8e1d5; --border2:#cfc5b5;
    --accent:#d9480f; --on-accent:#ffffff;
    --op:#2b8a6e; --str:#a16207; --kw:#6d4bb8;
  }
  @media (prefers-color-scheme: dark){
    :root:not([data-theme="light"]){
      --bg:#14120f; --surface:#1c1a16; --hero:#1f1b16; --fg:#ece6da; --muted:#9a9182; --border:#2c2924; --border2:#4a443b;
      --accent:#ff7a45; --on-accent:#1a120c;
      --op:#6cc4a1; --str:#e6c069; --kw:#b39ddb;
    }
  }
  :root[data-theme="dark"]{
    --bg:#14120f; --surface:#1c1a16; --hero:#1f1b16; --fg:#ece6da; --muted:#9a9182; --border:#2c2924; --border2:#4a443b;
    --accent:#ff7a45; --on-accent:#1a120c;
    --op:#6cc4a1; --str:#e6c069; --kw:#b39ddb;
  }
  *{box-sizing:border-box}
  html{scroll-behavior:smooth}
  body{margin:0; background:var(--bg); color:var(--fg);
    font:15px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
  .q,.target,.idx,.num{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,"Liberation Mono",monospace}

  /* Hero */
  .hero{display:flex; align-items:flex-end; justify-content:space-between; gap:24px; flex-wrap:wrap;
    padding:36px 40px 28px; background:linear-gradient(180deg,var(--hero),var(--bg)); border-bottom:1px solid var(--border)}
  .eyebrow{font-size:12px; letter-spacing:.18em; text-transform:uppercase; color:var(--accent); font-weight:700}
  .eyebrow b{color:var(--fg)}
  .target{margin:6px 0 12px; font-size:clamp(28px,4vw,46px); font-weight:700; line-height:1.1; letter-spacing:-.02em; word-break:break-all}
  .meta{display:flex; gap:8px; flex-wrap:wrap; font-size:13px; color:var(--muted)}
  .meta span{padding:3px 11px; border:1px solid var(--border); border-radius:999px; background:var(--surface)}
  .meta .mode{color:var(--accent); border-color:var(--accent); font-weight:600}
  .ring{display:flex; align-items:center; gap:14px}
  .ring svg{width:76px; height:76px; transform:rotate(-90deg)}
  .ring .trk{stroke:var(--border)}
  .ring .val{stroke:var(--accent); transition:stroke-dashoffset .3s}
  .ring b{display:block; font-size:24px; line-height:1.1}
  .ring small{display:block; color:var(--muted); font-size:12px}
  .link{border:0; background:none; padding:0; margin-top:4px; color:var(--accent); font:inherit; font-size:12px; cursor:pointer; text-decoration:underline; text-underline-offset:2px}

  /* Sticky toolbar: search + category chips */
  .bar{position:sticky; top:0; z-index:5; background:var(--bg); border-bottom:1px solid var(--border);
    padding:12px 40px 10px; display:flex; flex-direction:column; gap:10px}
  .row1{display:flex; gap:10px}
  .search{flex:1; min-width:0; padding:9px 14px; border:1px solid var(--border2); border-radius:10px;
    background:var(--surface); color:var(--fg); font:inherit; font-size:14px}
  .search:focus{outline:2px solid var(--accent); outline-offset:-1px}
  .btn{border:1px solid var(--border2); background:var(--surface); color:var(--fg); border-radius:10px;
    padding:8px 14px; font:inherit; font-size:13px; cursor:pointer}
  .btn:hover{border-color:var(--accent); color:var(--accent)}
  .chips{display:flex; gap:8px; overflow-x:auto; padding-bottom:4px; scrollbar-width:thin}
  .chip{white-space:nowrap; text-transform:uppercase; letter-spacing:.03em; border:1px solid var(--border); background:var(--surface); color:var(--muted);
    border-radius:999px; padding:4px 12px; font:inherit; font-size:12.5px; cursor:pointer}
  .chip:hover{color:var(--fg); border-color:var(--border2)}
  .chip .c{margin-left:6px; opacity:.7; font-variant-numeric:tabular-nums}
  .chip.on{background:var(--accent); border-color:var(--accent); color:var(--on-accent)}

  /* Sections + numbered rows */
  main{padding:4px 40px 40px}
  .cat{margin-top:30px; scroll-margin-top:120px}
  .cat-h{display:flex; align-items:baseline; gap:14px; padding-bottom:10px; border-bottom:2px solid var(--fg)}
  .idx{font-size:20px; font-weight:700; color:var(--accent)}
  .cat-h h2{margin:0; font-size:20px; font-weight:700; letter-spacing:.02em; text-transform:uppercase}
  .cat-h .n{margin-left:auto; color:var(--muted); font-size:13px; white-space:nowrap}
  ol.rows{list-style:none; margin:0; padding:0}
  li.d{display:grid; grid-template-columns:22px 40px minmax(0,1fr) auto; align-items:center; gap:14px;
    padding:11px 10px; border-bottom:1px solid var(--border)}
  li.d:hover{background:var(--surface)}
  .num{font-size:12px; color:var(--muted)}
  .chk{width:20px; height:20px; padding:0; border-radius:6px; border:1.5px solid var(--border2);
    background:transparent; color:transparent; font-size:12px; line-height:1; cursor:pointer}
  .chk:hover{border-color:var(--accent)}
  li.done .chk{background:var(--accent); border-color:var(--accent); color:var(--on-accent)}
  li.done .q,li.done .num{opacity:.5}
  .q{font-size:13.5px; line-height:1.6; color:var(--fg); text-decoration:none; word-break:break-word}
  .q:hover{text-decoration:underline; text-decoration-color:var(--accent); text-underline-offset:3px}
  .q .o{color:var(--op); font-weight:600}
  .q .s{color:var(--str)}
  .q .k{color:var(--kw); font-weight:700}
  button.cp{border:1px solid var(--border); background:transparent; color:var(--muted); border-radius:8px;
    padding:5px 12px; font:inherit; font-size:12px; cursor:pointer}
  button.cp:hover{color:var(--accent); border-color:var(--accent)}
  button.cp.ok{color:var(--on-accent); background:var(--accent); border-color:var(--accent)}
  .empty{display:none; color:var(--muted); text-align:center; padding:48px 0}
  .foot{color:var(--muted); font-size:12px; text-align:center; padding:24px 0 8px}
  a:focus-visible,button:focus-visible{outline:2px solid var(--accent); outline-offset:2px}

  @media (max-width:760px){
    .hero{padding:24px 16px 20px}
    .bar{padding:10px 16px 8px}
    main{padding:4px 16px 32px}
    li.d{grid-template-columns:22px minmax(0,1fr) auto; gap:10px; padding:10px 4px}
    .num{display:none}
    .idx,.cat-h h2{font-size:17px}
  }
  @media (prefers-reduced-motion: reduce){ html{scroll-behavior:auto} .ring .val{transition:none} }
</style>
</head>
<body data-target="${dom_esc}">
<header class="hero">
  <div>
    <div class="eyebrow">Recon<b>Dork</b> · Google dork report</div>
    <h1 class="target">${dom_esc}</h1>
    <div class="meta"><span class="mode">${mode_esc}</span><span id="total">0 dorks</span><span>Generated ${gen_esc}</span></div>
  </div>
  <div class="ring">
    <svg viewBox="0 0 76 76" aria-hidden="true"><circle class="trk" cx="38" cy="38" r="32" fill="none" stroke-width="7"/><circle class="val" id="ringval" cx="38" cy="38" r="32" fill="none" stroke-width="7" stroke-linecap="round"/></svg>
    <div><b id="pct">0%</b><small id="progtxt">0 opened</small><button class="link" id="reset" type="button">Reset progress</button></div>
  </div>
</header>
<div class="bar">
  <div class="row1">
    <input class="search" id="search" type="search" placeholder="Filter dorks…  ( / )" aria-label="Filter dorks">
    <button class="btn" id="theme" type="button" title="Toggle light/dark theme">Theme</button>
  </div>
  <div class="chips" id="chips" role="toolbar" aria-label="Categories"></div>
</div>
<main>
HTMLHEAD

# Lazy headers: a category's <h2> is held until its first dork is actually emitted,
# so a category whose dorks are all skipped (e.g. by de-duplication) produces no empty section.
open_sec=0; header_pending=0; pending_h2=""
flush_hdr(){
  (( header_pending )) || return 0
  printf '%s' "$pending_h2"
  open_sec=1; header_pending=0
}
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if [[ "$line" == \#* ]]; then
    (( open_sec )) && { echo "</ol></section>"; open_sec=0; }    # close the previous emitted category
    cat_name="${line#\# }"
    printf -v pending_h2 '<section class="cat"><header class="cat-h"><span class="idx"></span><h2 class="t">%s</h2><span class="n"></span></header>\n<ol class="rows">\n' "$(htmlesc "$cat_name")"
    header_pending=1                                 # hold until a dork is emitted
  else
    dork="${line//@SITE@/$SITE}"
    dork="${dork//@DOM@/$domain}"
    dork="${dork//@SINCE@/$SINCE}"
    dork="${dork//@NEG@/$NEG}"
    dork="${dork% }"                                 # drop the space left by an empty @NEG@
    # Guard: never emit a dork with an unresolved @PLACEHOLDER@ (e.g. a typo in the list).
    if [[ "$dork" =~ @[A-Z]+@ ]]; then
      echo "[!] Skipped malformed dork line: $line" >&2
      continue
    fi
    if [[ -n "${seen[$dork]:-}" ]]; then dupes=$((dupes+1)); continue; fi
    seen[$dork]=1
    total=$((total+1))
    flush_hdr
    enc="$(urlencode "$dork")"
    esc="$(htmlesc "$dork")"
    printf '<li class="d" data-q="%s"><button class="chk" type="button" title="Mark as done" aria-label="Mark as done">✓</button><span class="num"></span><a class="q" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer" href="%s%s%s">%s</a><button class="cp" type="button">Copy</button></li>\n' \
      "$esc" "$GB" "$enc" "$GB_TAIL" "$esc"
  fi
done <<< "$DORKS"
(( open_sec )) && echo "</ol></section>"

cat <<'HTMLFOOT'
<p class="empty" id="empty">No dorks match your filter.</p>
<p class="foot">Pace your searches to avoid Google CAPTCHAs. Only run these against assets you are authorized to test.</p>
</main>
<script>
(function(){
  var root=document.documentElement;
  var PREFIX='recondork:'+document.body.getAttribute('data-target')+':';
  function load(k){ try{ return localStorage.getItem(PREFIX+k); }catch(e){ return null; } }
  function save(k,v){ try{ localStorage.setItem(PREFIX+k,v); }catch(e){} }
  function loadTheme(){ try{ return localStorage.getItem('recondork:theme'); }catch(e){ return null; } }
  function saveTheme(v){ try{ localStorage.setItem('recondork:theme',v); }catch(e){} }

  // Theme: follow the OS unless the user picked one
  var t=loadTheme(); if(t) root.setAttribute('data-theme',t);
  document.getElementById('theme').addEventListener('click',function(){
    var cur=root.getAttribute('data-theme')||(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');
    var next=cur==='dark'?'light':'dark';
    root.setAttribute('data-theme',next); saveTheme(next);
  });

  // Syntax-highlight operators, quoted strings and OR (built with DOM nodes, never innerHTML)
  var RE=/("[^"]*")|(-?\b(?:site|inurl|intitle|intext|ext|filetype|after|before):)|(\bOR\b)/g;
  document.querySelectorAll('a.q').forEach(function(a){
    var s=a.textContent, last=0, m; a.textContent='';
    while((m=RE.exec(s))){
      if(m.index>last) a.appendChild(document.createTextNode(s.slice(last,m.index)));
      var sp=document.createElement('span'); sp.className=m[1]?'s':(m[2]?'o':'k'); sp.textContent=m[0];
      a.appendChild(sp); last=RE.lastIndex;
    }
    if(last<s.length) a.appendChild(document.createTextNode(s.slice(last)));
  });

  // Section numbers, counts and the category chips
  var sections=[].slice.call(document.querySelectorAll('section.cat'));
  var chipsEl=document.getElementById('chips'), chips=[], activeCat=null;
  function chip(label,count,idx){
    var b=document.createElement('button'), c=document.createElement('span');
    b.type='button'; b.className='chip'; b.textContent=label; c.className='c'; c.textContent=count;
    b.appendChild(c); chipsEl.appendChild(b); chips.push(b);
    b.addEventListener('click',function(){
      activeCat=idx; chips.forEach(function(x){ x.classList.toggle('on',x===b); });
      applyFilter();
      if(idx!==null) sections[idx].scrollIntoView({block:'start'}); else window.scrollTo(0,0);
    });
    return b;
  }
  var allItems=document.querySelectorAll('li.d').length;
  chip('All',allItems,null).classList.add('on');
  sections.forEach(function(sec,i){
    var n=sec.querySelectorAll('li.d').length;
    sec.querySelector('.idx').textContent=String(i+1).padStart(2,'0');
    sec.querySelector('.cat-h .n').textContent=n+(n===1?' dork':' dorks');
    chip(sec.querySelector('.cat-h .t').textContent,n,i);
  });

  // "Opened" tracking, remembered per target in this browser
  var items=[].slice.call(document.querySelectorAll('li.d'));
  var done={}; try{ done=JSON.parse(load('done')||'{}')||{}; }catch(e){ done={}; }
  document.getElementById('total').textContent=items.length+' dorks';
  var ring=document.getElementById('ringval'), C=2*Math.PI*32;
  ring.style.strokeDasharray=C;
  function progress(){
    var c=items.filter(function(li){ return li.classList.contains('done'); }).length;
    var p=items.length?c/items.length:0;
    ring.style.strokeDashoffset=C*(1-p);
    document.getElementById('pct').textContent=Math.round(p*100)+'%';
    document.getElementById('progtxt').textContent=c+' of '+items.length+' opened';
  }
  function mark(li,on){
    var k=li.getAttribute('data-q');
    li.classList.toggle('done',on);
    if(on) done[k]=1; else delete done[k];
    save('done',JSON.stringify(done)); progress();
  }
  items.forEach(function(li,i){
    li.querySelector('.num').textContent=String(i+1).padStart(2,'0');   // stable number, survives filtering
    if(done[li.getAttribute('data-q')]) li.classList.add('done');
    var a=li.querySelector('a.q');
    a.addEventListener('click',function(){ mark(li,true); });
    a.addEventListener('auxclick',function(e){ if(e.button===1) mark(li,true); });
    li.querySelector('.chk').addEventListener('click',function(){ mark(li,!li.classList.contains('done')); });
    li.querySelector('.cp').addEventListener('click',function(){ cp(this,li.getAttribute('data-q')); });
  });
  document.getElementById('reset').addEventListener('click',function(){
    done={}; save('done','{}'); items.forEach(function(li){ li.classList.remove('done'); }); progress();
  });
  progress();

  // Copy with Clipboard API, falling back to execCommand when blocked (e.g. file://)
  function cp(btn,t){
    var o='Copy';
    function fin(ok){ btn.textContent=ok?'Copied':'Failed'; btn.classList.toggle('ok',ok);
      setTimeout(function(){ btn.textContent=o; btn.classList.remove('ok'); },ok?1000:1500); }
    function fallback(){
      var ta=document.createElement('textarea');
      try{
        ta.value=t; ta.setAttribute('readonly',''); ta.style.position='fixed'; ta.style.opacity='0';
        document.body.appendChild(ta); ta.select(); fin(document.execCommand('copy'));
      }catch(e){ fin(false); }
      finally{ if(ta.parentNode) ta.parentNode.removeChild(ta); }
    }
    if(navigator.clipboard&&navigator.clipboard.writeText){
      navigator.clipboard.writeText(t).then(function(){ fin(true); }).catch(fallback);
    } else { fallback(); }
  }

  // Filter: chip category + every space-separated term must appear in the dork or its category
  var search=document.getElementById('search');
  function applyFilter(){
    var terms=search.value.toLowerCase().split(/\s+/).filter(Boolean), any=false;
    sections.forEach(function(sec,i){
      var cat=sec.querySelector('.cat-h .t').textContent.toLowerCase(), vis=0, hits=0;
      var inCat=(activeCat===null||activeCat===i);
      var rows=sec.querySelectorAll('li.d');
      rows.forEach(function(li){
        var hay=cat+' '+li.getAttribute('data-q').toLowerCase();
        var match=terms.every(function(w){ return hay.indexOf(w)!==-1; });
        var ok=inCat&&match;
        if(match) hits++;
        li.style.display=ok?'':'none'; if(ok) vis++;
      });
      sec.style.display=vis?'':'none';
      // hide a chip only when the search text matches nothing in it (not because another chip is selected)
      chips[i+1].style.display=(hits||activeCat===i)?'':'none';
      sec.querySelector('.cat-h .n').textContent=terms.length?vis+' of '+rows.length:rows.length+(rows.length===1?' dork':' dorks');
      if(vis) any=true;
    });
    document.getElementById('empty').style.display=any?'none':'block';
  }
  search.addEventListener('input',applyFilter);
  document.addEventListener('keydown',function(e){
    if(e.key==='/'&&document.activeElement!==search&&!/^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName)){
      e.preventDefault(); search.focus();
    }
    if(e.key==='Escape'&&document.activeElement===search){ search.value=''; applyFilter(); search.blur(); }
  });
})();
</script>
</body></html>
HTMLFOOT
} > "$out"

echo "[*] Dorks  : $total unique Google dorks (${dupes} duplicate(s) skipped)"
echo "[*] Report : $out"

# ---------------------------------------------------------------------------
# 7. Open in the browser (WSL-aware)
# ---------------------------------------------------------------------------
open_browser() {
  local f="$1"
  if command -v wslview >/dev/null 2>&1; then wslview "$f" >/dev/null 2>&1 && return 0; fi
  if command -v explorer.exe >/dev/null 2>&1; then
    explorer.exe "$(wslpath -w "$f" 2>/dev/null || echo "$f")" >/dev/null 2>&1; return 0
  fi
  # macOS: `open` is reliable and returns a real exit code (no $DISPLAY on a Mac).
  if [[ "$OSTYPE" == darwin* ]] && command -v open >/dev/null 2>&1; then
    open "$f" >/dev/null 2>&1 && return 0
  fi
  # Native Linux: only claim success if a GUI session actually exists, otherwise
  # a backgrounded xdg-open always "succeeds" and misreports on headless/SSH boxes.
  if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    if command -v xdg-open >/dev/null 2>&1; then xdg-open "$f" >/dev/null 2>&1 & return 0; fi
  fi
  return 1
}

if open_browser "$out"; then
  echo "[*] Opening in your browser. If nothing appears, open: $out"
else
  echo "[!] Could not auto-open a browser. Open this file manually:"
  echo "    $out"
fi
