# GitLab Member Management CLI

A PowerShell-based command-line tool for managing GitLab members across groups and projects. Supports listing memberships, setting expiration dates, and removing members while preserving existing access levels.

## Features

- **Group Member Listing**: List all members of a GitLab group and its subgroups
- **Project Member Listing**: List all members of a specific project (including inherited members)
- **User Membership Listing**: View all project memberships for a specific user across a group
- **Bulk Expiration Date Management**: Set expiration dates for a user across all their projects in a group
- **Single-Project Expiry**: Set expiration date for a user in a specific project
- **Member Removal**: Remove a user from all projects in a group, or from a specific project
- **Smart Removal**: Automatically detects group-level vs. project-level membership and uses the most efficient deletion path
- **Access Level Preservation**: Maintains existing access levels (Guest, Reporter, Developer, Maintainer, Owner) during updates
- **Subgroup Support**: Optionally include projects from all subgroups
- **Dry Run Mode**: Preview what would be changed without making any API updates
- **Parallel Processing**: Uses PowerShell 7+ parallel execution for faster membership scanning
- **Color-Coded Output**: Easy-to-read console output with color-coded success, warning, and error messages
- **Detailed Reporting**: Summary statistics by access level and expiry status

## Prerequisites

- **PowerShell**: Version 5.1 or higher (Windows PowerShell or PowerShell Core)
- **GitLab Personal Access Token**: With `api` scope
- **API Access**: Sufficient permissions to read and modify project members in the target group

## Installation

1. Clone or download this repository:
```powershell
git clone <repository-url>
cd gitlab-member-cli
```

2. No additional dependencies are required - the script uses built-in PowerShell cmdlets.

## Usage

### List members of projects in a group (and its subgroups)

```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "list" -Group "acme/product-a"
```

### List members of a project

```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "list" -Project "acme/product-a/auth-service"
```

### List memberships of a user under a group (and its subgroups)

```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "list" -Group "acme" -MemberUsername "username"
```

### Set expiration date for a user across all projects in a group

```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Group "acme" -MemberId 13624798 -ExpiryDate "2026-03-31"
```

### Set expiration date for a user in a specific project (by user ID)

```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Project "acme/product-a/auth-service" -MemberId 13624798 -ExpiryDate "2026-04-15"
```

### Set expiration date for a user in a specific project (by username)

```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Project "acme/product-a/auth-service" -MemberUsername "username" -ExpiryDate "2026-04-14"
```

### Remove a user from all projects in a group (and its subgroups)

```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Group "acme" -MemberUsername "username"
```

### Remove a user from a specific project

```powershell
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Project "acme/product-a/auth-service" -MemberUsername "username"
```

### Dry run — preview changes without applying them

```powershell
# Preview bulk set-expiry across a group
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Group "acme" -MemberUsername "username" -ExpiryDate "2026-04-30" -DryRun

# Preview single-project expiry update
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Project "acme/product-a/auth-service" -MemberUsername "username" -ExpiryDate "2026-04-30" -DryRun

# Preview remove across a group
.\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Group "acme" -MemberId 13624799 -DryRun
```

## Parameters

| Parameter           | Required      | Description                                                         | Default                     |
| ------------------- | ------------- | ------------------------------------------------------------------- | --------------------------- |
| `-PrivateToken`     | Yes           | GitLab Personal Access Token with API access                        | -                           |
| `-Operation`        | Yes           | Operation type: `list`, `set-expiry`, or `remove`                   | -                           |
| `-Group`            | Conditional†  | GitLab group path (e.g., `acme` or `acme/product-a`)    | -                           |
| `-Project`          | Conditional†  | GitLab project path (e.g., `acme/product-a/MyProject`)  | -                           |
| `-MemberUsername`   | Conditional*  | Username of the member to manage                                    | -                           |
| `-MemberId`         | Conditional*  | User ID of the member to manage                                     | -                           |
| `-ExpiryDate`       | Conditional** | Expiry date in YYYY-MM-DD format                                    | -                           |
| `-ServerUrl`        | No            | GitLab API URL                                                      | `https://gitlab.com/api/v4` |
| `-IgnoreSubgroups`  | No            | Exclude projects from nested subgroups when scanning memberships    | `false`                     |
| `-DryRun`           | No            | Preview what would be changed without making any API updates        | `false`                     |

† Exactly one of `-Group` or `-Project` must be specified.  
\* Required for `set-expiry` and `remove`; optional for `list` with `-Group` (omit to list all members).  
\*\* Required when `-Operation` is `set-expiry`.

**Target auto-detection based on parameters:**

| Parameters provided                      | Behavior                                                                        |
| ---------------------------------------- | ------------------------------------------------------------------------------- |
| `-Group` only                            | Lists all members of the group (including subgroups)                            |
| `-Group` + `-MemberUsername`/`-MemberId` | Lists, updates, or removes memberships for that user across all group projects  |
| `-Project`                               | Lists all members of the project                                                |
| `-Project` + `-MemberUsername`/`-MemberId` | Sets expiry or removes that user from the specific project                    |

## How It Works

**`-Group` only (list):**
1. Calls `GET /groups/{group}/members/all` with pagination to retrieve all group members (including inherited)
2. Displays UserId, Username, Name, AccessLevel, ExpiresAt with summary statistics

**`-Project` (list):**
1. Calls `GET /projects/{path}/members/all` with pagination to retrieve all project members (including inherited)
2. Displays UserId, Username, Name, AccessLevel, ExpiresAt with summary statistics

**`-Project` + user params (set-expiry):**
1. Resolves username to user ID if needed
2. Fetches current membership to preserve access level
3. Calls `PUT /projects/{path}/members/{user_id}` to update expiry on the single project

**`-Group` + user params (list, set-expiry, or remove):**
1. **User Resolution**: Converts username to user ID via GitLab API (if username provided)
2. **Project Discovery**: Fetches all projects in the group with pagination support
3. **Membership Scanning**: Iterates through projects (in parallel) to find where the user is a member
4. **Operation Execution**:
   - **List**: Displays membership details with summary statistics
   - **Set Expiry**: Bulk-updates expiration dates after user confirmation
   - **Remove**: Detects whether user has group-level or project-level membership, then removes accordingly (group-level removal automatically revokes inherited project access)

**`-Project` + user params (remove):**
1. Resolves username to user ID if needed
2. Verifies user is a direct member of the project (not just inherited)
3. Calls `DELETE /projects/{path}/members/{user_id}` to remove the membership

## Access Levels

The script recognizes and preserves the following GitLab access levels:

| Level      | Value | Permissions                     |
| ---------- | ----- | ------------------------------- |
| Guest      | 10    | Minimal read access             |
| Reporter   | 20    | Read access + issue management  |
| Developer  | 30    | Read/write access to code       |
| Maintainer | 40    | Full project management         |
| Owner      | 50    | Complete administrative control |

## Error Handling

- **User Not Found**: Script validates username exists before proceeding
- **Group Not Found**: Reports error if group is invalid or inaccessible
- **Project Not Found**: Reports error if project path is invalid or inaccessible
- **Permission Errors**: Catches and reports API permission issues
- **Invalid Date Format**: Validates date format before API calls
- **Partial Failures**: Reports success/failure for each project individually during bulk updates

## Security Considerations

- **Token Security**: Never commit your GitLab token to version control
- **Token Permissions**: Use tokens with minimum required permissions (API scope)
- **Dry Run First**: Use `-DryRun` to preview all changes before applying them
- **Confirmation Required**: All update operations (without `-DryRun`) require explicit user confirmation
- **Audit Trail**: GitLab maintains audit logs of all member changes

## Troubleshooting

### Issue: "User not found"
- Verify the username is correct and case-sensitive
- Ensure your token has permission to view users in the instance

### Issue: "Failed to fetch projects"
- Verify the group path is correct (e.g., `acme/product-a`)
- Check that your token has API access to the group
- Confirm your token hasn't expired

### Issue: "Permission denied" during set-expiry or remove
- Ensure your token has Maintainer or Owner permissions in the projects
- Verify the user has at least Maintainer role in the group

### Issue: Slow performance with many projects
- This is expected behavior - the script scans each project individually
- Consider using `-IgnoreSubgroups` to limit scope
- PowerShell 7+ uses parallel processing for significantly faster scanning

### Project Structure

```
gitlab-member-cli/
├── gitlab-member-cli.ps1    # Main script
└── README.md                # This file
```

---

**Note**: This tool performs bulk operations that can affect multiple projects and groups. Always use `-DryRun` to preview changes before applying them, especially when targeting large groups or running `remove` operations.
