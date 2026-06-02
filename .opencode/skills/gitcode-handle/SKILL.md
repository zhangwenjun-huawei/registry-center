---
name: gitcode-handle
description: >-
  Automate GitCode (gitcode.com) repository operations — create projects
  under personal or org namespace, delete repos, fork repos, push code,
  configure remotes. Use whenever the user asks to create, fork, delete,
  or manage repos on gitcode.com. Covers v3/v5 API differences, WAF cookie
  bypass, visibility traps, rate limits (1/min for fork), and the full
  create→push→fork workflow.
---

## GitCode API Operations

This skill handles all operations against GitCode (gitcode.com), Huawei's hosted Git service with a non-standard GitLab-compatible API.

### Environment

| Item | Value |
|------|-------|
| Web | `https://gitcode.com` |
| API Gateway | `https://api.gitcode.com` (Huawei Cloud APIG) |
| SSH | `git@gitcode.com:<namespace>/<repo>.git` |
| Backend | GitLab-compatible but NOT standard GitLab |

### API Version Matrix

| Version | Base URL | Status | Needs Cookie? |
|---------|----------|--------|---------------|
| v3 | `gitcode.com/api/v3/` | Works for project CREATE | Yes (WAF bypass) |
| v4 | `gitcode.com/api/v4/` | BLOCKED permanently | N/A (418 always) |
| v5 | `api.gitcode.com/api/v5/` | Best for query/delete/fork | No |

Rule: **v3 for CREATE, v5 for everything else.**

### Authentication

All requests use header: `PRIVATE-TOKEN: <personal_access_token>`

Token is obtained from GitCode personal settings → Access Tokens. Requires `api` + `write_repository` scopes.

### WAF Cookie Bypass (v3 only)

The CloudWAF on `gitcode.com` returns `418 I'm a Teapot` for any `/api/` request without a valid session cookie. **Always fetch the homepage first** to get cookies before making any v3 API calls:

```python
import urllib.request, http.cookiejar

cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
opener.open(urllib.request.Request("https://gitcode.com/",
    headers={"User-Agent": "Mozilla/5.0"}), timeout=15)
# Now v3 API calls through this opener will work
```

v5 API at `api.gitcode.com` does NOT require cookies.

### Create a Project (v3)

**Endpoint**: `POST https://gitcode.com/api/v3/projects`

**Minimum working payload**:
```json
{
  "name": "project-name",
  "path": "project-path",
  "visibility": "private"
}
```

**Critical rules**:
- `visibility` is REQUIRED and must be a STRING: `"private"`, `"internal"`, or `"public"`
- `visibility_level` (integer) does NOT work — this is NOT standard GitLab
- `path` cannot contain `/` — use separate `namespace_id` for org repos

**Common errors**:

| Error | Cause | Fix |
|-------|-------|-----|
| `可见性检验为空` | Missing `visibility` field | Add `"visibility": "private"` |
| `visibility校验不通过` | Wrong value type (integer 0) | Use string `"private"` |
| `AUDIT_FAILED` | Public visibility triggers audit | Use `"private"` |
| 500 System Error | Malformed JSON or encoding | Use `ensure_ascii=False`, `utf-8` |

### Create a Project Under an Organization (v5 → v3)

**Step 1**: Get the org's `namespace_id` via v5:
```python
# GET https://api.gitcode.com/api/v5/orgs/<org_name>
org = api_get(f"/api/v5/orgs/{org_name}")
namespace_id = org["id"]  # integer, e.g. 12165388 for OpenAN
```

**Step 2**: Create the project via v3 with `namespace_id`:
```python
result = api_post("/api/v3/projects", {
    "name": repo_name,
    "path": repo_name,
    "visibility": "private",
    "namespace_id": namespace_id,
}, use_v3=True)
```

### Query a Project (v5)

```
GET https://api.gitcode.com/api/v5/repos/<owner>/<repo>

Response:
{
  "id": 9976068,                          // integer ID
  "full_name": "OpenAN/a2at-orchestration-sdk",
  "ssh_url_to_repo": "git@gitcode.com:OpenAN/a2at-orchestration-sdk.git",
  "web_url": "https://gitcode.com/OpenAN/a2at-orchestration-sdk",
  ...
}
```

### List Org Repos (v5)

```
GET https://api.gitcode.com/api/v5/orgs/<org_name>/repos
```

### Delete a Project (v5)

```
DELETE https://api.gitcode.com/api/v5/repos/<owner>/<repo>
Returns: 204 No Content
```

v5 DELETE is more reliable than v3 DELETE. No cookie needed.

### Fork a Project (v5)

```
POST https://api.gitcode.com/api/v5/repos/<src_owner>/<src_repo>/forks
Body: {}   (empty JSON — auto-forks to authenticated user)
```

**Critical limits**:
- **Rate limit: 1 request per minute per user.** Exceeding returns `429 Too Many Requests`.
- **Always `time.sleep(65)` between fork-related operations.**
- If target namespace already has a repo with the same name, fork returns `422`. **Must DELETE the existing repo first, then fork.**

### Push Code

**Before committing and pushing, always pull from upstream first** to sync with the main repo and avoid overwriting others' changes:

```bash
# Sync with upstream (main/org repo) before making local changes
git fetch trunk
git merge trunk/master --no-edit

# Or if on a different branch:
git rebase trunk/master
```

**Rule**: Always run `git fetch trunk && git merge trunk/master` or `git pull trunk master` before starting work and before pushing. This ensures your local branch is up-to-date with the latest upstream code.

GitCode does NOT support push-to-create. Always create the empty repo via API first, then push via SSH:

```bash
git init
git add -A
git commit -m "Initial commit"
git remote add origin git@gitcode.com:<namespace>/<repo>.git
git push -u origin master
```

For forked repos, configure both remotes:
```bash
git remote add origin git@gitcode.com:<your_user>/<repo>.git     # personal fork
git remote add upstream git@gitcode.com:<org>/<repo>.git          # source repo
```

### Complete Workflow: Create Org Repo → Push → Fork to Personal

This is the standard pattern when contributing a new project to an organization on GitCode:

```python
import urllib.request, http.cookiejar, json, time, subprocess

TOKEN = "<token>"
ORG = "OpenAN"
REPO = "my-project"
USER = "ZhouJie6"

# ──── Setup: cookie jar + opener ────
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
opener.open(urllib.request.Request("https://gitcode.com/",
    headers={"User-Agent": "Mozilla/5.0"}), timeout=15)

def api_get(url, use_v3=False):
    base = "https://gitcode.com" if use_v3 else "https://api.gitcode.com"
    full_url = f"{base}{url}" if url.startswith("/") else url
    req = urllib.request.Request(full_url,
        headers={"PRIVATE-TOKEN": TOKEN, "Accept": "application/json"})
    r = opener.open(req, timeout=10)
    return json.loads(r.read().decode())

def api_post(url, payload, use_v3=False):
    base = "https://gitcode.com" if use_v3 else "https://api.gitcode.com"
    full_url = f"{base}{url}" if url.startswith("/") else url
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(full_url, data=data,
        headers={"PRIVATE-TOKEN": TOKEN, "Content-Type": "application/json; charset=utf-8"},
        method="POST")
    r = opener.open(req, timeout=15)
    return json.loads(r.read().decode())

def api_delete(url):
    full_url = f"https://api.gitcode.com{url}" if url.startswith("/") else url
    req = urllib.request.Request(full_url, headers={"PRIVATE-TOKEN": TOKEN}, method="DELETE")
    r = opener.open(req, timeout=15)
    return r.status

# 1. Get org namespace_id (v5)
org = api_get(f"/api/v5/orgs/{ORG}")
org_id = org["id"]

# 2. Create under org (v3, needs cookie)
result = api_post("/api/v3/projects", {
    "name": REPO, "path": REPO, "visibility": "private", "namespace_id": org_id,
}, use_v3=True)
ssh_url = result["ssh_url_to_repo"]

# 3. Pull latest from upstream before pushing local changes
subprocess.run(["git", "fetch", "trunk"], check=True)
subprocess.run(["git", "merge", "trunk/master", "--no-edit"], check=True)

# 4. Push code
subprocess.run(["git", "remote", "add", "org", ssh_url], check=True)
subprocess.run(["git", "push", "org", "master"], check=True)

# 4. Delete existing personal repo if present (v5)
api_delete(f"/api/v5/repos/{USER}/{REPO}")

# 5. Wait for rate limit (CRITICAL: fork is 1/min)
time.sleep(65)

# 6. Fork from org to personal (v5)
fork_result = api_post(f"/api/v5/repos/{ORG}/{REPO}/forks", {})
fork_ssh = fork_result.get("ssh_url_to_repo",
    f"git@gitcode.com:{USER}/{REPO}.git")

# 7. Set up local remotes
subprocess.run(["git", "remote", "remove", "origin"], capture_output=True)
subprocess.run(["git", "remote", "remove", "org"], capture_output=True)
subprocess.run(["git", "remote", "add", "origin", fork_ssh], check=True)
subprocess.run(["git", "remote", "add", "upstream", ssh_url], check=True)
```

### ID Format Differences

| Context | v3 | v5 |
|---------|----|----|
| User ID | MongoDB ObjectID (24-char hex) | Integer |
| Project ID | MongoDB ObjectID (24-char hex) | Integer |
| Org ID | — | Integer |

IDs from v3 and v5 are NOT interchangeable.

### Summary Checklist

1. Always fetch gitcode.com homepage first for v3 cookie
2. v3 (with cookie) → project creation only
3. v5 (no cookie) → query, delete, fork, org lookup
4. v4 → dead, don't try
5. `visibility` is a required STRING, not integer
6. Fork rate limit: 1/min → `sleep(65)` between operations
7. Delete same-name personal repo before forking
8. No push-to-create — API first, then git push
9. Use SSH for git push, not HTTPS
10. Fork repos: `origin` = personal, `upstream` = org source
11. **Before committing: pull from upstream** (`git fetch trunk && git merge trunk/master`) to sync with main repo and avoid overwriting others' changes
12. Commit messages: use English, conventional commit format (`fix:`, `feat:`, `refactor:`, `docs:`, `chore:`) with concise summaries. Never commit `.env`, `llm_config.json`, or files containing API keys. Stage selectively with `git add <file>...` — do NOT use `git add -A` or `git add .` when sensitive files are modified. Exclude sensitive files from staging; never `git checkout` them to discard the working copy content.
