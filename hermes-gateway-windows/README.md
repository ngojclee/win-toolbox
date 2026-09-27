# Hermes Agent on Windows — hidden dashboard, gateway autostart, log hygiene

Operational notes for running [Hermes Agent](https://hermes-agent.nousresearch.com/docs) unattended on a
Windows box: how the web dashboard is started hidden and locked down, where every file lives, and how to
keep the log directory from eating the disk.

Everything below was verified on Windows 11 with `hermes` 2026-09 (venv install under
`%LOCALAPPDATA%\hermes\hermes-agent`). Placeholders: `<USER>` = Windows account, `<PANEL_PORT>` = dashboard
port (e.g. 9119), `<PROFILE>` = Hermes profile name.

> **No credentials in this repo.** Commands that touch a password or secret always read it from a file or
> from an environment variable the runner sets — never type a real value into a documented command.

---

## 1. Where Hermes keeps its files

```
%LOCALAPPDATA%\hermes\hermes-agent\venv\Scripts\hermes.exe   ← install + venv (the per-profile venv may be
                                                                %LOCALAPPDATA%\hermes\app\venv on older installs
                                                                — always verify the path exists)
%LOCALAPPDATA%\hermes\                                      ← root HERMES_HOME (default profile + shared state)
    config.yaml  .env  cron\  sessions\  skills\  plugins\  memories\  logs\  state\
%LOCALAPPDATA%\hermes\profiles\<PROFILE>\                   ← one HERMES_HOME per named profile
    config.yaml  .env  logs\
%LOCALAPPDATA%\hermes\profiles\<PROFILE>\logs\              ← gateway.log, agent.log, gui.log, errors.log,
                                                              dashboard-auth.log, mcp-stderr.log
%LOCALAPPDATA%\hermes\gateway-service\Hermes_Gateway.{cmd,vbs}                     ← generated gateway launcher
%LOCALAPPDATA%\hermes\profiles\<PROFILE>\gateway-service\Hermes_Gateway_<PROFILE>.{cmd,vbs}
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Hermes_Gateway_<PROFILE>.vbs  ← logon autostart
```

Profile ≠ install: `HERMES_HOME` selects the data root, the venv holds the code. A gateway/dashboard process
started **without** `-p <PROFILE>` uses the root `HERMES_HOME`.

## 2. Dashboard that never shows a console window

`hermes.exe` is a pip console-script, so it spawns its own console — `powershell -WindowStyle Hidden` does
**not** hide it. Use a VBS wrapper with window style `0`, which hides the whole process tree:

```vbs
' serve_runner.vbs
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\<USER>\serve_runner.ps1""", 0, False
```

Register it as a logon task (no elevation needed for the current user):

```powershell
$action  = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument '"C:\Users\<USER>\serve_runner.vbs"'
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName 'Hermes-Dashboard-<PANEL_PORT>' -Action $action -Trigger $trigger -Force
```

Verify it is really hidden and up — never assume:

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'hermes.exe.+dashboard' } |
  ForEach-Object { $p = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
                   '{0} handle={1}' -f $_.ProcessId, $p.MainWindowHandle }   # handle=0  → hidden
netstat -ano | findstr :<PANEL_PORT> | findstr LISTENING
curl.exe -s -o NUL -w "%{http_code}`n" http://127.0.0.1:<PANEL_PORT>/login        # 200
```

A task whose action is `wscript.exe <file>.vbs` flips back to `State=Ready` immediately after firing —
that is normal, the service stays detached.

## 3. Dashboard auth: hash, never plaintext

The dashboard refuses to bind a non-loopback address without an auth provider, so a wrong/absent config
looks like "process runs, no LISTENING socket".

**Auth comes from the runner's environment, not from `config.yaml`.** The basic-auth provider only
registers from the process's *launch scope*; a `dashboard.basic_auth` block in another profile is ignored
with `... ignoring it because dashboard auth is owned by launch scope <x>` in `errors.log`. Set these in
the runner script before launching `hermes dashboard`:

```powershell
$env:HERMES_DASHBOARD_BASIC_AUTH_USERNAME      = '<DASH_USER>'
$env:HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH = '<scrypt-hash>'          # never the plaintext password
$env:HERMES_DASHBOARD_BASIC_AUTH_SECRET        = (Get-Content 'C:\Users\<USER>\hermes-gw-secret.txt' -Raw).Trim()
$env:HERMES_DASHBOARD_SESSION_TOKEN            = (Get-Content 'C:\Users\<USER>\hermes-gw-token.txt' -Raw).Trim()
```

- Precompute the hash so the plaintext never sits on disk:
  `python -c "import sys; sys.path.insert(0, r'<hermes-agent>'); from plugins.dashboard_auth.basic import hash_password; print(hash_password('...'))"`
  (the docs call this surface `password_hash`; "the plaintext then never sits at rest").
- `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` (plaintext env) **overrides** a password hash — delete it.
- `..._SECRET` is the HMAC key for session cookies: keep it stable across restarts, treat any exposure as
  burned, and remember that rotating it logs every client out.
- Lock the secret file down to the running user only:
  `icacls C:\Users\<USER>\hermes-gw-secret.txt /inheritance:r /grant:r "<MACHINE>\<USER>:(R)"`

Prove the credentials work instead of trusting the config:

```bash
curl -s http://<HOST>:<PANEL_PORT>/api/auth/providers      # {"providers":[{"name":"basic",...}]}
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://<HOST>:<PANEL_PORT>/auth/password-login \
     -H 'Content-Type: application/json' \
     -d '{"provider":"basic","username":"<DASH_USER>","password":"<from your vault>"}'   # 200 + cookie
# wrong password → 401
```

## 4. Gateway autostart is generated — don't hand-roll it

Hermes writes its own per-profile launcher (`gateway-service\Hermes_Gateway_<PROFILE>.vbs`) and copies it
into the Startup folder; it runs it with `sh.Run "wscript.exe <target>", 0, False` (hidden). That is the
whole logon mechanism.

**Pitfall:** hand-written `hermes_gw_restart_<PROFILE>.cmd` scripts plus `HermesRestart*` scheduled tasks
silently die the moment the install moves — one machine still called
`...\hermes\app\venv\Scripts\hermes.exe` long after the venv had moved to `...\hermes-agent\venv\...`, so
the tasks had been no-ops for weeks. Check `Test-Path` on a launcher's target before trusting it, then
delete the dead script + task:

```powershell
schtasks /delete /tn HermesRestart<PROFILE> /f
Get-ScheduledTask | Where-Object { $_.TaskName -match 'Hermes' } |
  ForEach-Object { $_.TaskName + '  (' + $_.State + ')' }
```

## 5. Log hygiene

| File | Rotates? | Notes |
|---|---|---|
| `gui.log`, `agent.log`, `desktop.log` | yes (`.1`…`.5`, 5–10 MB) | the rotated copies are the safe cleanup target |
| `gateway.log`, `errors.log`, `dashboard-auth.log` | no | usually small; watch `errors.log` |
| `mcp-stderr.log` | **no** | unbounded — it is the stderr of every MCP server Hermes spawns |

`mcp-stderr.log` is delimited per server start:

```
===== [2026-08-20 01:40:10] starting MCP server 'regional-search' =====
```

A crashing MCP server retries in a loop and appends a full Node stack trace each time, which is how a
single misconfigured server grew this file to 50 MB / 963k lines:

```powershell
Select-String -Path "$env:LOCALAPPDATA\hermes\profiles\<PROFILE>\logs\mcp-stderr.log" -Pattern 'ERR_MODULE_NOT_FOUND' |
  Measure-Object                                 # 37k hits = a server is dead, fix it first
grep -o "Cannot find package '[^']*'" mcp-stderr.log | sort | uniq -c   # e.g. Cannot find package 'zod'
```

Fix the server (or drop it from the profile's `mcp:` block in `config.yaml`), then rotate the log during a
gateway restart window — do **not** truncate it while the gateway holds it open (Windows keeps the writer's
offset and the file refills with NUL padding).

Safe cleanup recipe (zip first, never touch the active file, and re-glob after deleting — reusing a stale
file list raises `FileNotFoundError`):

```python
rotated = [f for f in logs if ".log." in os.path.basename(f) or f.endswith(".old")]
old     = [f for f in rotated if time.time() - os.path.getmtime(f) > 7*86400]
# zip `old` to a scratch dir, then os.remove() each, then re-list for the report
```

`%LOCALAPPDATA%\hermes\_trash_hermes_agent\venv.stale.<ts>` is a leftover from a Hermes self-update and is
safe to delete.

## 6. Other pitfalls worth remembering

- **Never kill processes by matching a string that appears in your own command line.** A `Where-Object`
  loop matching `'dashboard'` also matched the running `bash`/`powershell` that hosted the loop and killed
  the session. Match on the real binary/cmdline shape (`hermes.exe.+dashboard`) or use the pid from
  `netstat`.
- Do **not** launch the dashboard in the foreground over SSH to debug it: the pip console-script wrapper
  keeps stdout open, so the SSH call hangs even after it prints its startup banner. Read the port and the
  log files instead.
- Under MSYS/git-bash, inline PowerShell with `$_`, `{}`, `|` gets mangled — write a `.ps1`/`.py` file and
  run that. `$env:APPDATA` inside an inline PowerShell command often comes back empty; `ls "$APPDATA/..."`
  from bash works.
- Rotating the dashboard secret logs out every browser, including the peer machine that had the panel open
  in a tab.
