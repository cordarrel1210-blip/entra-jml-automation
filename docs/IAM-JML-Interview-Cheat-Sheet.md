# IAM JML Automation — Interview Cheat Sheet

## 30-second project summary

I built and tested a PowerShell and Microsoft Graph workflow that automates the Joiner–Mover–Leaver lifecycle in Microsoft Entra ID. It validates HR-style CSV requests, creates or updates identities, assigns department-based access, removes outdated access, disables leavers, revokes sessions, verifies the result, and writes audit logs. I also added preview checks, duplicate protection, encrypted temporary credentials, and safe reruns.

## Explain the lifecycle

| Event | Process |
|---|---|
| Joiner | Validate input → create account → assign department group → verify → audit |
| Mover | Validate change → grant new access → update attributes → remove old access → verify → audit |
| Leaver | Validate request → disable account → revoke sessions → remove access → verify → audit |

## Commands worth recognizing

| Command | Purpose |
|---|---|
| `Connect-MgGraph` | Authenticate to Microsoft Graph with required scopes |
| `Get-MgUser` | Find a user and inspect identity or account state |
| `New-MgUser` | Create a joiner account |
| `Update-MgUser` | Change attributes or disable an account |
| `Get-MgGroup` | Resolve the correct access group |
| `New-MgGroupMember` | Assign group-based access |
| `Remove-MgGroupMemberByRef` | Remove outdated group access |
| `Revoke-MgUserSignInSession` | Invalidate a leaver's active sessions |
| `Import-Csv` / `Export-Csv` | Read requests and write audit records |
| `Get-Help <command> -Examples` | Confirm exact syntax when needed |

You do **not** need to memorize every parameter. Know what each command accomplishes, how the objects flow through the script, and how you would verify the outcome.

## Security and reliability controls

- Least-privilege Graph scopes for the required identity and group operations.
- Input validation and Employee ID checks before making changes.
- Preview scripts so changes can be reviewed before execution.
- Idempotency: a repeated run detects the completed state and safely skips it.
- New access is assigned before old access is removed during a mover event.
- Temporary credentials are encrypted locally and excluded through `.gitignore`.
- Passwords and secrets are never written to audit logs or the public repository.
- Every lifecycle action records timestamp, employee ID, action, status, and details.

## Strong troubleshooting story

**Situation:** The joiner accounts and group memberships were created, but exporting encrypted temporary credentials failed with an `op_Addition` error.

**Task:** Recover safely without creating duplicate accounts or losing credential control.

**Action:** I inspected Entra ID to establish the actual state, confirmed the users already existed, traced the problem to a single imported PowerShell object being treated differently from an array, and wrapped it with `@(...)`. I then used a controlled recovery script to reset and securely preserve the affected credentials.

**Result:** The workflow completed successfully, duplicate users were avoided, group assignments remained correct, and recovery actions were auditable.

## Likely interview questions

**Why disable a leaver instead of immediately deleting the account?**  
Disabling blocks access immediately while preserving the identity for investigation, retention, ownership transfer, or a formal deletion policy.

**Why revoke sign-in sessions?**  
Disabling prevents new authentication, but existing tokens or sessions may remain valid. Revocation reduces that exposure.

**What is idempotency?**  
Running the same request again produces no harmful duplicate change. My scripts check the current state and report `Skipped` when it is already correct.

**How did you prevent excessive access during a mover event?**  
I mapped departments to approved groups, assigned the required target group, removed the previous department group, and verified both states.

**How did you validate success?**  
I queried the user's attributes, account status, group memberships, and session-revocation timestamp, then reviewed the lifecycle audit CSV.

**What would you improve for production?**  
Use app-only authentication with a managed identity or certificate, stronger approval workflows, centralized protected logging, alerting, automated tests, CI/CD, and formal access reviews.

## Honest answer about assistance

“I built this in a lab with guided assistance and documentation. I understand the lifecycle design, security controls, and troubleshooting decisions, and I can explain or modify the workflow. Like engineers in production, I use `Get-Help` and official documentation to confirm exact syntax instead of relying on memory.”

## What to practice before an interview

1. Deliver the 30-second summary without reading it.
2. Explain one lifecycle from input through verification and audit.
3. Describe the troubleshooting story using Situation, Task, Action, Result.
4. Recognize the eight Microsoft Graph commands above and state their purpose.
5. Be ready to share one production improvement and why it matters.
