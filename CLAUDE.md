# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains a PowerShell CLI tool for managing GitLab member expiration dates across all projects in a group. It allows bulk operations to list memberships, set expiration dates, and remove members while preserving existing access levels.

## Running the Script

The main script is `gitlab-member-cli.ps1`. It requires PowerShell and accepts the following operations:

**List members of projects in a group (and its subgroups):**
```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "list" -Group "acme/product-a"
```

**List members of a project:**
```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "list" -Project "acme/product-a/auth-service"
```

**List memberships of a user under a group (and its subgroups):**
```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "list" -Group "acme" -MemberUsername "username"
```

**Set expiration date for a user across all projects in a group:**
```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Group "acme" -MemberId 13624798 -ExpiryDate "2026-03-31"
```

**Set expiration date for a user in a specific project (by user ID):**
```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Project "acme/product-a/auth-service" -MemberId 13624798 -ExpiryDate "2026-04-15"
```

**Set expiration date for a user in a specific project (by username):**
```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Project "acme/product-a/auth-service" -MemberUsername "username" -ExpiryDate "2026-04-14"
```

**Remove a user from all projects in a group (and its subgroups):**
```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Group "acme" -MemberUsername "username"
```

**Remove a user from a specific project:**
```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Project "acme/product-a/auth-service" -MemberUsername "username"
```

**Dry run remove (preview without applying):**
```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Group "acme" -MemberId 13624798 -DryRun
```

**Key Parameters:**
- `-PrivateToken`: GitLab Personal Access Token (required)
- `-Group`: GitLab group path (mutually exclusive with `-Project`)
- `-Project`: GitLab project path (mutually exclusive with `-Group`)
- `-Operation`: Either "list", "set-expiry", or "remove" (required)
- `-MemberUsername` or `-MemberId`: Identify the member (required for set-expiry and remove; optional for list with -Group)
- `-ExpiryDate`: YYYY-MM-DD format (required for set-expiry)
- `-ServerUrl`: GitLab API URL (defaults to "https://gitlab.com/api/v4")
- `-IgnoreSubgroups`: Exclude nested subgroup projects when scanning user memberships (default: subgroups are included)
- `-DryRun`: Preview what would be changed without making any API updates (set-expiry and remove)

## Architecture

The script follows a functional structure with these main components:

**User Resolution (`Get-GitLabUser`):**
- Converts username to user ID via GitLab API
- Used when `-MemberUsername` is provided instead of `-MemberId`

**Group/Project Info (`Get-GitLabGroup`, `Get-GitLabProject`):**
- Fetches group or project metadata (name, ID, path) for display
- Used before listing members to show the full path and numeric ID

**Project Discovery (`Get-GitLabProjects`):**
- Paginated fetching of all projects in a group
- Supports subgroup inclusion
- Returns complete project list for membership scanning

**Membership Scanning (`Get-MembershipDetails`):**
- Iterates through all projects checking for member access
- Collects access level, expiry date, and project details
- Uses GET /projects/{id}/members/{user_id} endpoint
- Silently skips projects where user is not a member
- Uses parallel processing (PS7+) or background jobs (PS5.1)

**Member Listing (`Get-GroupMembers`, `Get-ProjectMembers`, `Show-MemberList`):**
- `Get-GroupMembers`: calls GET /groups/{group}/members/all with pagination
- `Get-ProjectMembers`: calls GET /projects/{path}/members/all with pagination
- `Show-MemberList`: shared display function with access level and expiry summaries

**Expiry Updates (`Set-MemberExpiry`, `Set-ProjectMemberExpiry`):**
- `Set-MemberExpiry`: bulk update across multiple projects; requires confirmation (skipped in dry run)
- `Set-ProjectMemberExpiry`: update a single project; fetches current access level to preserve it
- Both use PUT /projects/{id}/members/{user_id} with access_level + expires_at
- Preserves existing access level (Guest=10, Reporter=20, Developer=30, Maintainer=40, Owner=50)
- Both support `-DryRun`: prints a preview table of what would change without making any API calls

**Group Discovery (`Get-GitLabDescendantGroups`):**
- Fetches all descendant groups (at all levels) under a given group
- Uses GET /groups/{id}/descendant_groups with pagination
- Used by the `remove` operation to find groups where the user may be a direct member

**Group Membership Scanning (`Get-GroupMembershipDetails`):**
- Scans a list of groups to find which ones the user is a DIRECT member of
- Uses GET /groups/{id}/members/{user_id} (not `/members/all`) — so inherited access is excluded
- Returns GroupId, GroupPath, AccessLevel, ExpiresAt per group

**Member Removal (`Remove-MemberFromGroups`, `Remove-MemberFromGroup`, `Remove-ProjectMember`):**
- `Remove-MemberFromGroups`: bulk removal from groups via DELETE /groups/{id}/members/{user_id}; preferred when user has group-level membership (inherited project access is revoked automatically)
- `Remove-MemberFromGroup`: bulk removal across multiple projects (fallback when no group memberships found); requires confirmation (skipped in dry run)
- `Remove-ProjectMember`: removes a single project membership; verifies user is a direct member first
- All support `-DryRun`: prints a preview table of what would be removed without making any API calls
- The `remove` operation automatically detects whether user has group-level or project-level membership and uses the appropriate deletion path

**Color-Coded Output:**
- Header (Cyan), Success (Green), Warning (Yellow), Error (Red), Info (White), Dim (DarkGray)
- Defined in `$script:ColorScheme` hashtable

## MCP Configuration

The `.vscode/mcp.json` file configures the GitLab MCP server for Claude Code:
- Uses `@zereight/mcp-gitlab@2.0.25` package
- Prompts for GitLab token and API URL on first use
- Wiki, milestone, and pipeline features disabled (read-only mode: false)

## Development Guidelines

**Using Context7 for GitLab API Documentation:**

When implementing new features or modifying existing API interactions, ALWAYS use the Context7 MCP to retrieve the latest GitLab API documentation. This ensures compatibility with current API versions and best practices.

Steps to follow:
1. Use ToolSearch to load the Context7 tool: `query: "context7"`
2. Call `mcp__context7__query-docs` or `mcp__claude_ai_Context7__query-docs` with queries like:
   - "GitLab API project members endpoint"
   - "GitLab API update member expiration"
   - "GitLab API group projects pagination"
3. Review the returned documentation before making API changes
4. Verify endpoint paths, parameter names, and response structures match current API specs

**Example Context7 usage:**
```
When adding a new feature to manage group-level members (not just project members):
- Query: "GitLab API group members management"
- Review: Endpoint differences between /groups/{id}/members and /projects/{id}/members
- Implement: New function following documented patterns
```

This practice prevents breaking changes from API version updates and ensures the tool uses officially supported endpoints and parameters.

## Error Handling

- Script validates parameters (date format, required fields, -Group/-Project mutual exclusivity)
- API errors are caught and reported per-operation
- User not found, group not found, and permission errors are handled gracefully
- 404 responses during membership scanning are expected (user not a member) and silently skipped

## Git Commit Guidelines

When creating git commits, use standard commit messages without attribution to external tools:

```bash
git commit -m "Add organization management features

- Implement complete organization CRUD operations
- Add domain verification and member management
- Include comprehensive integration tests
- Update documentation and roadmap"
```

Do NOT include attribution lines like:
- "Generated with [Claude Code](https://claude.ai/code)"
- "via [Happy](https://happy.engineering)"
- "Co-Authored-By: Claude <noreply@anthropic.com>"
- "Co-Authored-By: Happy <yesreply@happy.engineering>"

Keep commit messages focused on the technical changes and their business value.