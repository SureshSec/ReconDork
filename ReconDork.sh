#!/usr/bin/env bash
#
# ReconDork.sh - Bug bounty Google dork generator
#
# Builds clickable Google-search links for a target domain, writes a timestamped
# dark-themed HTML page and optional plain-text list, then opens it.
#
set -euo pipefail
# Treat '&' in ${var//pat/repl} replacements as a literal, not the matched text
# (bash 5.2+ patsub_replacement); keeps htmlesc and placeholder substitution safe.
shopt -u patsub_replacement 2>/dev/null || true

usage() {
cat <<'U'
ReconDork.sh - Bug bounty Google dork generator

Usage:
  ./ReconDork.sh example.com             # Search the domain (site:example.com).
  ./ReconDork.sh -w example.com          # Wildcard: search the subdomains (site:*.example.com).
U
exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# 1. Parse arguments
# ---------------------------------------------------------------------------
NOOPEN=0; WANT_TXT=0; WILD=0; OUTDIR="."; DOMAIN_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--wild)     WILD=1 ;;
    --no-open)     NOOPEN=1 ;;
    -t|--txt)      WANT_TXT=1 ;;
    -o|--out)
      if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
        echo "Error: $1 requires a directory argument." >&2; usage 1
      fi
      OUTDIR="$2"; shift ;;
    -h|--help)     usage 0 ;;
    -*)            echo "Unknown option: $1" >&2; usage 1 ;;
    *)
      if [[ -n "$DOMAIN_ARG" ]]; then
        echo "Error: only one target domain allowed (got '$DOMAIN_ARG' and '$1')." >&2; usage 1
      fi
      DOMAIN_ARG="$1" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# 2. Get + normalize + strictly validate the domain
# ---------------------------------------------------------------------------
domain="$DOMAIN_ARG"
if [[ -z "$domain" ]]; then
  read -rp "Enter target domain (e.g. example.com): " domain || {
    echo "Error: no domain provided (stdin closed)." >&2; exit 1; }
fi

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
if [[ ! "$domain" =~ $hostname_re ]]; then
  echo "Invalid domain: '$domain'" >&2
  echo "Expected something like: example.com, sub.example.co.uk, or an xn-- IDN host." >&2
  exit 1
fi

# @SITE@ = target used as a site: operator (flag-controlled).
# @SUB@  = subdomain-discovery scope; follows the chosen mode (equals @SITE@).
# @DOM@  = bare domain as a quoted search string (never wildcarded).
if [[ "$WILD" == 1 ]]; then
  SITE="*.$domain"; MODE="WILDCARD SEARCH (site:*.$domain — subdomains)"
else
  SITE="$domain";   MODE="DOMAIN SEARCH (site:$domain)"
fi
SUB="$SITE"          # subdomain-discovery dorks follow the chosen scope

echo "[*] Target : $domain"
echo "[*] Mode   : $MODE"
[[ "$WILD" == 0 ]] && echo "[i] Use -w/--wild for a wildcard (*.$domain) subdomain search."
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
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# 4. Dork list. Lines starting with '#' (or '#!') are category headers.
#    Placeholders: @SITE@ (flag-controlled), @SUB@ (= @SITE@), @DOM@ (bare).
# ---------------------------------------------------------------------------
read -r -d '' DORKS <<'EOF' || true
#! Subdomain discovery
site:@SUB@ -site:www.@DOM@
site:@SUB@ (inurl:dev OR inurl:staging OR inurl:test OR inurl:uat OR inurl:qa OR inurl:beta OR inurl:sandbox OR inurl:preprod)
site:@SUB@ (inurl:internal OR inurl:corp OR inurl:intranet OR inurl:vpn OR inurl:portal OR inurl:gateway OR inurl:admin)
site:@SUB@ (inurl:jenkins OR inurl:gitlab OR inurl:jira OR inurl:confluence OR inurl:grafana OR inurl:kibana OR inurl:api)
#! Secrets & tokens
site:@SITE@ "type": "service_account"
site:@SITE@ ("client_email" "private_key")
site:@SITE@ "SENDGRID_API_KEY"
site:@SITE@ ("DB_PASSWORD" OR "DATABASE_URL" OR "SECRET_KEY" OR "API_KEY" OR "PRIVATE_KEY" OR "client_secret")
site:@SITE@ ("AWS_ACCESS_KEY_ID" OR "AWS_SECRET_ACCESS_KEY")
site:@SITE@ ("api_key" OR "apikey" OR "secret_key" OR "access_token" OR "private_key")
site:@SITE@ ("jdbc:" OR "mongodb://" OR "postgres://" OR "mysql://")
site:@SITE@ ("Authorization: Bearer" OR "authorization: token")
site:@SITE@ (ext:htpasswd OR ext:pem OR ext:key)
site:@SITE@ ("BEGIN PRIVATE KEY" OR "BEGIN RSA PRIVATE KEY" OR "BEGIN OPENSSH PRIVATE KEY" OR "BEGIN EC PRIVATE KEY")
#! Environment & config files
site:@SITE@ (inurl:.env OR inurl:.env.local OR inurl:.env.production OR inurl:.env.backup OR inurl:.env.dev OR inurl:.env.staging)
site:@SITE@ (inurl:web.config OR inurl:appsettings.json OR inurl:local.settings.json)
site:@SITE@ (inurl:config.php OR inurl:configuration.php OR inurl:settings.py OR inurl:application.properties OR inurl:application.yml)
site:@SITE@ (inurl:wp-config.php.bak OR inurl:config.php.bak OR inurl:web.config.bak OR inurl:settings.py.bak)
site:@SITE@ (inurl:credentials OR inurl:.aws/credentials OR inurl:sftp-config.json OR inurl:config.json)
site:@SITE@ ("APP_KEY=" OR "JWT_SECRET=" OR "DB_PASSWORD=" OR "REDIS_PASSWORD=" OR "MAIL_PASSWORD=" OR "SECRET_KEY=")
#! IaC & DevOps state files
site:@SITE@ (ext:tfstate OR inurl:terraform.tfstate)
site:@SITE@ (ext:tfvars OR inurl:terraform.tfvars)
site:@SITE@ (inurl:kubeconfig OR inurl:.kube/config OR ext:kubeconfig)
site:@SITE@ (inurl:Dockerfile OR inurl:docker-compose.yml OR inurl:docker-compose.yaml)
site:@SITE@ (inurl:.gitlab-ci.yml OR inurl:.travis.yml OR inurl:Jenkinsfile OR inurl:.circleci)
site:@SITE@ (inurl:.npmrc OR inurl:.pypirc OR inurl:.netrc OR inurl:.dockercfg OR inurl:.docker/config.json)
site:@SITE@ inurl:gradle.properties
site:@SITE@ (inurl:.bash_history OR inurl:.zsh_history OR inurl:.mysql_history)
site:@SITE@ (ext:ipynb OR inurl:.ipynb_checkpoints)
site:@SITE@ inurl:postman_collection.json
#! Version control & config exposure
site:@SITE@ inurl:.git/config
site:@SITE@ (inurl:.svn OR inurl:.svn/entries)
site:@SITE@ inurl:.DS_Store
site:@SITE@ inurl:wp-config.php
site:@SITE@ inurl:phpinfo.php
site:@SITE@ (inurl:wp-content OR inurl:wp-includes OR inurl:wp-admin OR inurl:wp-json)
# Top params — XSS
site:@SITE@ (inurl:q= OR inurl:s= OR inurl:search= OR inurl:query= OR inurl:keyword= OR inurl:keywords= OR inurl:searchterm= OR inurl:id= OR inurl:page= OR inurl:view= OR inurl:type= OR inurl:name=)
site:@SITE@ (inurl:title= OR inurl:subject= OR inurl:message= OR inurl:comment= OR inurl:content= OR inurl:body= OR inurl:text= OR inurl:value= OR inurl:input= OR inurl:field= OR inurl:data= OR inurl:email=)
site:@SITE@ (inurl:url= OR inurl:redirect= OR inurl:return= OR inurl:callback= OR inurl:jsonp= OR inurl:lang= OR inurl:year= OR inurl:month= OR inurl:image= OR inurl:terms= OR inurl:key= OR inurl:tag=)
site:@SITE@ (inurl:label= OR inurl:description= OR inurl:filter= OR inurl:sort= OR inurl:order= OR inurl:display= OR inurl:output= OR inurl:ref= OR inurl:category= OR inurl:categoryid= OR inurl:begindate= OR inurl:enddate=)
# Top params — SQL Injection
site:@SITE@ (inurl:id= OR inurl:page= OR inurl:report= OR inurl:dir= OR inurl:search= OR inurl:category= OR inurl:categoryid= OR inurl:file= OR inurl:class= OR inurl:url= OR inurl:news= OR inurl:item=)
site:@SITE@ (inurl:menu= OR inurl:lang= OR inurl:name= OR inurl:ref= OR inurl:title= OR inurl:view= OR inurl:topic= OR inurl:thread= OR inurl:type= OR inurl:date= OR inurl:form= OR inurl:main=)
site:@SITE@ (inurl:nav= OR inurl:region= OR inurl:order= OR inurl:sort= OR inurl:filter= OR inurl:product= OR inurl:productid= OR inurl:pid= OR inurl:uid= OR inurl:user= OR inurl:userid= OR inurl:cat=)
site:@SITE@ (inurl:catid= OR inurl:group= OR inurl:groupid= OR inurl:key= OR inurl:query= OR inurl:select= OR inurl:number= OR inurl:num= OR inurl:offset= OR inurl:limit= OR inurl:status= OR inurl:state=)
# Top params — LFI / Path Traversal
site:@SITE@ (inurl:file= OR inurl:filepath= OR inurl:file_path= OR inurl:filename= OR inurl:file_name= OR inurl:path= OR inurl:pathname= OR inurl:dir= OR inurl:directory= OR inurl:folder= OR inurl:root= OR inurl:rootpath=)
site:@SITE@ (inurl:home= OR inurl:page= OR inurl:pg= OR inurl:include= OR inurl:inc= OR inurl:require= OR inurl:load= OR inurl:read= OR inurl:retrieve= OR inurl:fetch= OR inurl:locate= OR inurl:show=)
site:@SITE@ (inurl:doc= OR inurl:document= OR inurl:pdf= OR inurl:img= OR inurl:image= OR inurl:photo= OR inurl:template= OR inurl:tpl= OR inurl:view= OR inurl:display= OR inurl:content= OR inurl:layout=)
site:@SITE@ (inurl:data= OR inurl:resource= OR inurl:source= OR inurl:src= OR inurl:location= OR inurl:loc= OR inurl:download= OR inurl:attachment= OR inurl:item= OR inurl:style= OR inurl:log= OR inurl:target=)
site:@SITE@ (inurl:cat= OR inurl:action= OR inurl:board= OR inurl:date= OR inurl:detail= OR inurl:prefix= OR inurl:mod= OR inurl:conf= OR inurl:site= OR inurl:type= OR inurl:name= OR inurl:ref=)
# Top params — SSRF
site:@SITE@ (inurl:url= OR inurl:uri= OR inurl:dest= OR inurl:destination= OR inurl:redirect= OR inurl:redirect_uri= OR inurl:redirect_url= OR inurl:continue= OR inurl:return= OR inurl:next= OR inurl:data= OR inurl:reference=)
site:@SITE@ (inurl:site= OR inurl:html= OR inurl:path= OR inurl:domain= OR inurl:callback= OR inurl:feed= OR inurl:host= OR inurl:port= OR inurl:to= OR inurl:out= OR inurl:window= OR inurl:val=)
site:@SITE@ (inurl:validate= OR inurl:remote= OR inurl:fetch= OR inurl:proxy= OR inurl:api= OR inurl:endpoint= OR inurl:server= OR inurl:target= OR inurl:forward= OR inurl:go= OR inurl:u= OR inurl:link=)
site:@SITE@ (inurl:link_url= OR inurl:image_url= OR inurl:resource= OR inurl:load= OR inurl:image= OR inurl:img= OR inurl:src= OR inurl:source= OR inurl:open= OR inurl:get= OR inurl:view= OR inurl:dir=)
# Top params — RCE
site:@SITE@ (inurl:cmd= OR inurl:exec= OR inurl:command= OR inurl:execute= OR inurl:ping= OR inurl:query= OR inurl:jump= OR inurl:code= OR inurl:reg= OR inurl:do= OR inurl:func= OR inurl:arg=)
site:@SITE@ (inurl:option= OR inurl:load= OR inurl:process= OR inurl:step= OR inurl:read= OR inurl:feature= OR inurl:exe= OR inurl:module= OR inurl:payload= OR inurl:run= OR inurl:print= OR inurl:system=)
site:@SITE@ (inurl:shell= OR inurl:call= OR inurl:function= OR inurl:action= OR inurl:method= OR inurl:cli= OR inurl:upload= OR inurl:eval= OR inurl:script= OR inurl:task= OR inurl:op= OR inurl:mode=)
# Top params — Open Redirect
site:@SITE@ (inurl:next= OR inurl:url= OR inurl:target= OR inurl:rurl= OR inurl:dest= OR inurl:destination= OR inurl:redir= OR inurl:redirect_uri= OR inurl:redirect_url= OR inurl:redirect= OR inurl:out= OR inurl:view=)
site:@SITE@ (inurl:to= OR inurl:image_url= OR inurl:go= OR inurl:return= OR inurl:returnTo= OR inurl:return_to= OR inurl:checkout_url= OR inurl:continue= OR inurl:return_path= OR inurl:redirect_to= OR inurl:returnurl= OR inurl:return_url=)
site:@SITE@ (inurl:forward= OR inurl:location= OR inurl:goto= OR inurl:link= OR inurl:callback= OR inurl:success= OR inurl:cancel= OR inurl:back= OR inurl:ref= OR inurl:referer= OR inurl:u= OR inurl:r=)
#! Confidential & internal documents
site:@SITE@ ("confidential" OR "not for distribution" OR "not for public release" OR "restricted" OR "proprietary" OR "do not distribute") filetype:pdf
site:@SITE@ "for internal use only" (ext:pdf OR ext:doc OR ext:docx OR ext:xls OR ext:xlsx OR ext:ppt OR ext:pptx)
site:@SITE@ ("192.168" OR "10.0.0" OR "172.16" OR "172.31") (ext:pdf OR ext:txt OR ext:log OR ext:xls OR ext:xlsx)
site:@SITE@ ("internal." OR "intranet." OR "corp." OR "vpn." OR ".local") filetype:pdf
site:@SITE@ ("password" OR "credentials") (ext:xls OR ext:xlsx OR ext:doc OR ext:docx OR ext:pdf OR ext:txt)
site:@SITE@ ("username" "password") (ext:xls OR ext:xlsx OR ext:csv OR ext:txt)
#! Data dumps & PII
site:@SITE@ (ext:xls OR ext:xlsx OR ext:csv) ("email" OR "phone" OR "ssn" OR "salary" OR "dob")
site:@SITE@ (ext:csv OR ext:xlsx) ("customer" OR "employee" OR "contact list")
site:@SITE@ (ext:csv OR ext:txt) "@gmail.com"
#! Application & database logs
site:@SITE@ (inurl:debug.log OR inurl:error.log OR inurl:access.log OR inurl:application.log OR inurl:laravel.log)
site:@SITE@ (inurl:database.sql OR inurl:backup.sql OR inurl:dump.sql)
site:@SITE@ (inurl:.sql.gz OR inurl:.sql.zip OR inurl:.sql.bak)
site:@SITE@ inurl:wp-content/debug.log
# File-upload & import endpoints
site:@SITE@ (inurl:upload OR inurl:uploads OR inurl:fileupload OR inurl:import)
site:@SITE@ (inurl:upload.php OR inurl:upload.aspx OR inurl:upload.jsp)
# Backup & source & temp & archive files
site:@SITE@ (inurl:.php.bak OR inurl:.php.old OR inurl:.php.save OR inurl:.php.txt)
site:@SITE@ (ext:inc OR ext:tpl OR ext:phps OR inurl:.asp.bak)
site:@SITE@ (inurl:.orig OR inurl:.tmp OR inurl:.copy)
site:@SITE@ (inurl:backup OR inurl:bak OR inurl:dump) (ext:zip OR ext:tar OR ext:gz OR ext:rar OR ext:7z)
site:@SITE@ (inurl:backup.zip OR inurl:site-backup OR inurl:db_backup OR inurl:full_backup OR inurl:www.zip OR inurl:site.zip)
# Files & extensions
site:@SITE@ (ext:log OR ext:txt OR ext:conf OR ext:cnf OR ext:ini OR ext:env OR ext:sh OR ext:bak OR ext:backup OR ext:swp OR ext:old)
site:@SITE@ (ext:yml OR ext:yaml OR ext:toml OR ext:properties OR ext:config OR ext:cfg)
site:@SITE@ (ext:sql OR ext:dump OR ext:db OR ext:sqlite OR ext:sqlite3)
site:@SITE@ (ext:zip OR ext:rar OR ext:tar OR ext:gz)
site:@SITE@ (filetype:xls OR filetype:xlsx OR filetype:csv OR filetype:pdf OR filetype:doc OR filetype:docx OR filetype:ppt OR filetype:pptx)
# Directory listing
site:@SITE@ intitle:"Index of"
site:@SITE@ "Index of /"
site:@SITE@ "Index of" ("backup" OR ".git" OR "uploads" OR "files")
# Admin & auth panels & login
site:@SITE@ (inurl:admin OR inurl:administrator OR inurl:login OR inurl:signin OR inurl:auth OR inurl:dashboard)
site:@SITE@ (intitle:login OR intitle:"sign in" OR inurl:secure OR inurl:portal)
site:@SITE@ (inurl:phpmyadmin OR inurl:pma OR intitle:"phpMyAdmin")
site:@SITE@ (inurl:jenkins OR intitle:"Dashboard [Jenkins]")
site:@SITE@ (inurl:grafana OR intitle:"Grafana")
site:@SITE@ (inurl:kibana OR inurl:app/kibana)
site:@SITE@ (inurl:gitlab OR inurl:jira OR inurl:confluence)
site:@SITE@ (intitle:"Actuator" OR inurl:actuator/health OR inurl:actuator/env)
site:@SITE@ (inurl:actuator/info OR inurl:actuator/metrics OR inurl:actuator/mappings OR inurl:actuator/beans OR inurl:actuator/heapdump OR inurl:actuator/threaddump OR inurl:actuator/configprops)
site:@SITE@ (inurl:solr OR inurl:elasticsearch OR inurl:_search)
# Signup & reset & invite flows
site:@SITE@ (inurl:register OR inurl:signup OR inurl:reset OR inurl:forgot OR inurl:invite OR inurl:activate)
# Tech & legacy endpoints
site:@SITE@ (ext:php OR ext:aspx OR ext:jsp OR ext:do OR ext:action OR ext:cgi)
# GraphQL & extra API surfaces
site:@SITE@ (inurl:graphql OR inurl:graphiql OR inurl:graphql-playground OR inurl:altair)
site:@SITE@ (ext:wsdl OR inurl:wsdl)
site:@SITE@ (inurl:api/v1 OR inurl:api/v2 OR inurl:api/v3 OR inurl:rest/api OR inurl:/rest)
# API docs & specifications
site:@SITE@ (inurl:swagger OR inurl:swagger-ui OR inurl:api-docs OR inurl:apidocs OR inurl:openapi OR inurl:redoc OR inurl:api-explorer)
site:@SITE@ (intitle:"Swagger UI" OR inurl:openapi.json OR inurl:openapi.yaml OR inurl:swagger.json OR inurl:swagger.yaml)
site:@SITE@ (inurl:v2/api-docs OR inurl:v3/api-docs OR inurl:swagger/v1/swagger.json)
site:@SITE@ filetype:json "swagger"
# Identity & auth provider config
site:@SITE@ (inurl:.well-known/openid-configuration OR inurl:.well-known/oauth-authorization-server)
site:@SITE@ (inurl:jwks OR inurl:jwks.json OR inurl:.well-known/jwks)
site:@SITE@ (inurl:saml/metadata OR inurl:adfs/ls OR inurl:protocol/openid-connect OR inurl:auth/realms)
site:@SITE@ (inurl:oauth/authorize OR inurl:connect/authorize OR inurl:as/authorization.oauth2)
site:@SITE@ (inurl:saml OR inurl:sso OR inurl:oauth OR inurl:.well-known)
# Server status & info pages
site:@SITE@ (inurl:server-status OR inurl:server-info)
site:@SITE@ intitle:"phpinfo()"
site:@SITE@ (inurl:CFIDE OR inurl:cfcache)
# Cross-domain & CORS policy files
site:@SITE@ (inurl:crossdomain.xml OR inurl:clientaccesspolicy.xml)
# Errors & debug leakage
site:@SITE@ ("stack trace" OR "exception" OR "SQL syntax" OR "Traceback" OR "Fatal error" OR "Warning:" OR "database error" OR "undefined index" OR "unhandled exception")
site:@SITE@ (intitle:"exception" OR intitle:"server at" OR inurl:error)
site:@SITE@ (inurl:debug OR inurl:test OR inurl:dev OR inurl:staging OR inurl:sandbox OR inurl:uat OR inurl:qa OR inurl:demo OR inurl:temp OR inurl:internal)
# WordPress-specific leaks
site:@SITE@ inurl:wp-content/uploads (ext:sql OR ext:zip OR ext:txt OR ext:log)
site:@SITE@ inurl:wp-json/wp/v2/users
# Off-site: cloud storage
site:s3.amazonaws.com "@DOM@"
site:*.s3.amazonaws.com "@DOM@"
site:storage.googleapis.com "@DOM@"
site:firebasestorage.googleapis.com "@DOM@"
site:*.firebasedatabase.app "@DOM@"
site:blob.core.windows.net "@DOM@"
site:*.blob.core.windows.net "@DOM@"
site:cloudfront.net "@DOM@"
site:azurewebsites.net "@DOM@"
site:dev.azure.com "@DOM@"
site:*.digitaloceanspaces.com "@DOM@"
site:*.r2.dev "@DOM@"
site:*.aliyuncs.com "@DOM@"
# Off-site: third-party SaaS
site:*.zendesk.com "@DOM@"
site:*.freshdesk.com "@DOM@"
site:*.herokuapp.com "@DOM@"
site:*.sharepoint.com "@DOM@"
site:box.com "@DOM@"
# Off-site: shared docs
site:docs.google.com "@DOM@"
site:docs.google.com inurl:"/d/" "@DOM@"
site:drive.google.com "@DOM@"
site:docs.google.com/spreadsheets "@DOM@"
site:dropbox.com/s "@DOM@"
site:*-my.sharepoint.com "@DOM@"
site:onedrive.live.com "@DOM@"
EOF

# ---------------------------------------------------------------------------
# 5. Output paths (timestamped so re-runs never clobber earlier reports)
# ---------------------------------------------------------------------------
mkdir -p "$OUTDIR"
ts="$(date +%Y%m%d-%H%M%S)"
tag="domain"; [[ "$WILD" == 1 ]] && tag="wild"
out="$OUTDIR/recondork_${domain}_${tag}_${ts}.html"
txt="$OUTDIR/recondork_${domain}_${tag}_${ts}.txt"
GB="https://www.google.com/search?q="
dom_esc="$(htmlesc "$domain")"

# ---------------------------------------------------------------------------
# 6. Emit HTML + optional plain-text, de-duplicated
# ---------------------------------------------------------------------------
declare -A seen=()
total=0; dupes=0
[[ "$WANT_TXT" == 1 ]] && { printf '# Google dorks for %s  (%s)\n' "$domain" "$MODE" > "$txt"; }

{
cat <<HTMLHEAD
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>[recon] ${dom_esc}</title>
<style>
  :root{
    --bg:#060912; --card:#0e1626; --fg:#c3d5f5; --dim:#5a7aa8;
    --acc:#29d3ff; --acc2:#7ee8ff; --star:#ffd93d; --bd:#1e3250;
  }
  *{box-sizing:border-box}
  html,body{margin:0}
  body{
    background:
      radial-gradient(1200px 600px at 80% -10%, #0e1e38 0%, transparent 60%),
      radial-gradient(900px 500px at -10% 110%, #0c1730 0%, transparent 55%),
      var(--bg);
    color:var(--fg);
    font:16px/1.65 "JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,Consolas,"Courier New",monospace;
    padding:28px; min-height:100vh;
  }
  /* CRT scanlines */
  body::before{
    content:""; position:fixed; inset:0; pointer-events:none; z-index:9;
    background:repeating-linear-gradient(to bottom, rgba(41,211,255,.035) 0 1px, transparent 1px 3px);
    mix-blend-mode:screen; opacity:.6;
  }
  h1{
    font-size:23px; line-height:1.4; margin:0 0 18px; color:var(--acc); letter-spacing:.02em;
    text-shadow:0 0 6px rgba(41,211,255,.55), 0 0 18px rgba(41,211,255,.25);
  }
  h1 b{color:var(--acc2); font-weight:700}
  h1 .count{color:inherit; font-size:inherit; font-weight:inherit; text-shadow:inherit}
  h1 .cur{display:inline-block; width:9px; height:18px; margin-left:4px; background:var(--acc);
    vertical-align:-3px; animation:blink 1.1s steps(1) infinite; box-shadow:0 0 8px var(--acc)}
  @keyframes blink{50%{opacity:0}}
  h2{font-size:15px; text-transform:uppercase; letter-spacing:.1em; color:var(--acc2);
    margin:26px 0 10px; padding-bottom:7px; border-bottom:1px dashed var(--bd)}
  h2 .star{color:var(--star); text-shadow:0 0 8px rgba(255,217,61,.45)}
  ul{list-style:none; padding:0; margin:0}
  li.d{display:flex; gap:8px; align-items:stretch; margin:0 0 6px}
  a{flex:1; padding:11px 14px; font-size:15px; line-height:1.5; background:var(--card); border:1px solid var(--bd); border-radius:6px;
    color:var(--fg); text-decoration:none; word-break:break-word; transition:.12s}
  a::before{content:"$ "; color:var(--dim)}
  a:hover{border-color:var(--acc); color:var(--acc2); background:#122038; box-shadow:0 0 12px rgba(41,211,255,.18)}
  button.cp{flex:0 0 auto; padding:0 12px; background:#070b16; border:1px solid var(--bd); border-radius:6px;
    color:var(--dim); font:inherit; font-size:13px; cursor:pointer; transition:.12s}
  button.cp:hover{border-color:var(--acc); color:var(--acc); box-shadow:0 0 10px rgba(41,211,255,.25)}
  /* Keyboard focus (accessibility) */
  a:focus-visible,button.cp:focus-visible{outline:2px solid var(--acc); outline-offset:2px; color:var(--acc2)}
  .count{color:var(--dim); font-size:13px}
  /* Respect users who ask for less motion */
  @media (prefers-reduced-motion: reduce){
    h1 .cur{animation:none}
    body::before{display:none}
  }
  ::selection{background:rgba(41,211,255,.3); color:#eaf6ff}
</style>
</head>
<body>
<h1>All the Google dorks generated against your target domain <b>${dom_esc}</b> - <span class="count" id="count"></span><span class="cur"></span></h1>
HTMLHEAD

# Lazy headers: a category's <h2> is held until its first dork is actually emitted,
# so a category whose dorks are all skipped (e.g. by de-duplication) produces no empty section.
open_ul=0; header_pending=0; pending_h2=""; pending_txt=""
flush_hdr(){
  (( header_pending )) || return 0
  printf '%s' "$pending_h2"
  [[ "$WANT_TXT" == 1 ]] && printf '%s' "$pending_txt" >> "$txt"
  open_ul=1; header_pending=0
}
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if [[ "$line" == \#* ]]; then
    (( open_ul )) && { echo "</ul>"; open_ul=0; }    # close the previous emitted category
    if [[ "$line" == '#!'* ]]; then cat_name="${line#\#! }"; else cat_name="${line#\# }"; fi
    star='<span class="star">★</span> '              # star on every section title
    printf -v pending_h2 '<h2>%s%s</h2>\n<ul>\n' "$star" "$(htmlesc "$cat_name")"
    [[ "$WANT_TXT" == 1 ]] && printf -v pending_txt '\n# ★ %s\n' "$cat_name"
    header_pending=1                                 # hold until a dork is emitted
  else
    dork="${line//@SITE@/$SITE}"
    dork="${dork//@SUB@/$SUB}"
    dork="${dork//@DOM@/$domain}"
    if [[ -n "${seen[$dork]:-}" ]]; then dupes=$((dupes+1)); continue; fi
    seen[$dork]=1
    total=$((total+1))
    flush_hdr
    enc="$(urlencode "$dork")"
    esc="$(htmlesc "$dork")"
    printf '<li class="d"><button class="cp" data-q="%s" onclick="cp(this)">copy</button><a target="_blank" rel="noopener" href="%s%s">%s</a></li>\n' \
      "$esc" "$GB" "$enc" "$esc"
    [[ "$WANT_TXT" == 1 ]] && printf '%s\n' "$dork" >> "$txt"
  fi
done <<< "$DORKS"
(( open_ul )) && echo "</ul>"

cat <<'HTMLFOOT'
<script>
function cp(btn){
  var t=btn.getAttribute('data-q'), o=btn.textContent;
  function done(okk){ btn.textContent=okk?'[ok]':'[copy failed]'; setTimeout(function(){btn.textContent=o;},okk?900:1500); }
  function fallback(){                       // execCommand path when Clipboard API is blocked
    var ta=document.createElement('textarea');
    try{
      ta.value=t; ta.setAttribute('readonly','');
      ta.style.position='fixed'; ta.style.opacity='0';
      document.body.appendChild(ta); ta.select();
      done(document.execCommand('copy'));
    }catch(e){ done(false); }
    finally{ if(ta.parentNode) ta.parentNode.removeChild(ta); }  // always clean up
  }
  if(navigator.clipboard && navigator.clipboard.writeText){
    navigator.clipboard.writeText(t).then(function(){done(true);}).catch(fallback);
  } else { fallback(); }
}
document.getElementById('count').textContent=document.querySelectorAll('li.d').length+' dorks';
</script>
</body></html>
HTMLFOOT
} > "$out"

abs="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
echo "[*] Dorks  : $total unique Google dorks (${dupes} duplicate(s) skipped)"
echo "[*] Report : $abs"
[[ "$WANT_TXT" == 1 ]] && echo "[*] Text   : $(cd "$(dirname "$txt")" && pwd)/$(basename "$txt")"

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
    if command -v open      >/dev/null 2>&1; then open "$f"      >/dev/null 2>&1 & return 0; fi
  fi
  return 1
}

if [[ "$NOOPEN" == 1 ]]; then
  echo "[*] --no-open set. Open it yourself: $abs"
elif open_browser "$abs"; then
  echo "[*] Opening in your browser. If nothing appears, open: $abs"
else
  echo "[!] Could not auto-open a browser. Open this file manually:"
  echo "    $abs"
fi
