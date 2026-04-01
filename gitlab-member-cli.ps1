<#
.SYNOPSIS
    GitLab Member Management CLI - Manage project member expirations across a group

.DESCRIPTION
    This script allows you to list members and update member expiration dates within
    a GitLab group or project. It preserves existing access levels during updates.

    Target is determined automatically from the parameters provided:
      - -Group only              : List all members of the group (including subgroups)
      - -Group + user params     : List/update memberships for a specific user across all projects in the group
      - -Project                 : List all members of the project, or set expiry for a specific user in the project

.PARAMETER PrivateToken
    GitLab Personal Access Token with API access

.PARAMETER Group
    GitLab group path (e.g., 'acme' or 'acme/product-a')

.PARAMETER Project
    GitLab project path (e.g., 'acme/product-a/auth-service')

.PARAMETER Operation
    Operation to perform: 'list' or 'set-expiry'

.PARAMETER MemberUsername
    Username of the member to manage (e.g., 'CalvinLee')

.PARAMETER MemberId
    User ID of the member to manage (alternative to MemberUsername)

.PARAMETER ExpiryDate
    Expiry date in YYYY-MM-DD format (required for 'set-expiry' operation)

.PARAMETER IgnoreSubgroups
    Exclude projects from nested subgroups when scanning user memberships. By default, subgroups are included.

.PARAMETER IncludeSubgroups
    Deprecated. Use -IgnoreSubgroups instead.

.PARAMETER DryRun
    Preview what would be changed without making any API updates. Skips confirmation prompt.

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "list" -Group "acme/product-a"

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "list" -Project "acme/product-a/auth-service"

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "list" -Group "acme" -MemberUsername "username"

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Group "acme" -MemberId 13624798 -ExpiryDate "2026-03-31"

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Project "acme/product-a/auth-service" -MemberId 13624798 -ExpiryDate "2026-04-15"

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Project "acme/product-a/auth-service" -MemberUsername "username" -ExpiryDate "2026-04-14"

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Group "acme" -MemberUsername "username" -ExpiryDate "2026-04-30" -DryRun

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "set-expiry" -Project "acme/product-a/auth-service" -MemberUsername "username" -ExpiryDate "2026-04-30" -DryRun

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Group "acme" -MemberUsername "username"

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Group "acme" -MemberUsername "username" -IgnoreSubgroups

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Group "acme" -MemberId 13624798 -DryRun

.EXAMPLE
    .\gitlab-member-cli.ps1 -PrivateToken "glpat-xxx" -Operation "remove" -Project "acme/product-a/auth-service" -MemberUsername "username"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "GitLab Personal Access Token")]
    [ValidateNotNullOrEmpty()]
    [string]$PrivateToken,

    [Parameter(Mandatory = $false, HelpMessage = "GitLab group path (e.g., 'acme' or 'acme/product-a')")]
    [string]$Group,

    [Parameter(Mandatory = $false, HelpMessage = "GitLab project path (e.g., 'acme/product-a/auth-service')")]
    [string]$Project,

    [Parameter(Mandatory = $true, HelpMessage = "Operation: 'list', 'set-expiry', or 'remove'")]
    [ValidateSet("list", "set-expiry", "remove")]
    [string]$Operation,

    [Parameter(Mandatory = $false, HelpMessage = "Member username")]
    [string]$MemberUsername,

    [Parameter(Mandatory = $false, HelpMessage = "Member user ID")]
    [int]$MemberId,

    [Parameter(Mandatory = $false, HelpMessage = "Expiry date (YYYY-MM-DD)")]
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$ExpiryDate,

    [Parameter(Mandatory = $false, HelpMessage = "GitLab server URL")]
    [ValidateNotNullOrEmpty()]
    [string]$ServerUrl = "https://gitlab.com/api/v4",

    [Parameter(Mandatory = $false, HelpMessage = "Exclude projects from nested subgroups (default: subgroups are included)")]
    [switch]$IgnoreSubgroups,

    [Parameter(Mandatory = $false, HelpMessage = "Deprecated: use -IgnoreSubgroups instead")]
    [System.Nullable[bool]]$IncludeSubgroups,

    [Parameter(Mandatory = $false, HelpMessage = "Preview changes without making any updates")]
    [switch]$DryRun
)

# Trim trailing slashes from ServerUrl
$ServerUrl = $ServerUrl.TrimEnd('/')

# Handle deprecated -IncludeSubgroups parameter
if ($null -ne $IncludeSubgroups) {
    Write-Warning "-IncludeSubgroups is deprecated. Use -IgnoreSubgroups instead."
    if (-not $IncludeSubgroups) {
        $IgnoreSubgroups = $true
    }
}

# Color scheme
$script:ColorScheme = @{
    Header  = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error   = "Red"
    Info    = "White"
    Dim     = "DarkGray"
}

function Write-Header {
    param([string]$Message)
    $separator = '=' * 70
    Write-Host "`n$separator" -ForegroundColor $ColorScheme.Header
    Write-Host $Message -ForegroundColor $ColorScheme.Header
    Write-Host "$separator" -ForegroundColor $ColorScheme.Header
}

function Write-Success {
    param([string]$Message)
    Write-Host "OK $Message" -ForegroundColor $ColorScheme.Success
}

function Write-Warn {
    param([string]$Message)
    Write-Host "WARNING $Message" -ForegroundColor $ColorScheme.Warning
}

function Write-Err {
    param([string]$Message)
    Write-Host "ERROR $Message" -ForegroundColor $ColorScheme.Error
}

function Get-GitLabUser {
    param(
        [string]$Username,
        [string]$ServerUrl,
        [hashtable]$Headers
    )

    try {
        $uri = "$ServerUrl/users?username=$Username"
        $users = Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop
        if ($users.Count -eq 0) {
            Write-Err "User '$Username' not found"
            return $null
        }
        return $users[0]
    }
    catch {
        Write-Err "Failed to fetch user '$Username': $_"
        return $null
    }
}

function Get-GitLabGroup {
    param(
        [string]$Group,
        [string]$ServerUrl,
        [hashtable]$Headers
    )

    try {
        $encodedGroup = [Uri]::EscapeDataString($Group)
        $uri = "$ServerUrl/groups/$encodedGroup"
        return Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop
    }
    catch {
        Write-Err "Failed to fetch group info for '$Group': $_"
        return $null
    }
}

function Get-GitLabProject {
    param(
        [string]$Project,
        [string]$ServerUrl,
        [hashtable]$Headers
    )

    try {
        $encodedPath = [Uri]::EscapeDataString($Project)
        $uri = "$ServerUrl/projects/$encodedPath"
        return Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop
    }
    catch {
        Write-Err "Failed to fetch project info for '$Project': $_"
        return $null
    }
}

function Get-GitLabProjects {
    param(
        [string]$Group,
        [string]$ServerUrl,
        [bool]$IgnoreSubgroups,
        [hashtable]$Headers
    )

    Write-Host "`nFetching projects from group '$Group'..." -ForegroundColor $ColorScheme.Info

    $allProjects = @()
    $page = 1
    $perPage = 100
    $encodedGroup = [Uri]::EscapeDataString($Group)

    do {
        try {
            $uri = "$ServerUrl/groups/$encodedGroup/projects?per_page=$perPage&page=$page"
            if (-not $IgnoreSubgroups) {
                $uri = $uri + "&include_subgroups=true"
            }

            $response = Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop
            $allProjects += $response

            Write-Host "  Fetched page $page - $($response.Count) projects" -ForegroundColor $ColorScheme.Dim
            $page++
        }
        catch {
            Write-Err "Failed to fetch projects: $_"
            return $null
        }
    } while ($response.Count -eq $perPage)

    Write-Success "Found $($allProjects.Count) total projects"
    return $allProjects
}

function Get-GroupMembers {
    param(
        [string]$Group,
        [string]$ServerUrl,
        [hashtable]$Headers
    )

    Write-Host "`nFetching members of group '$Group'..." -ForegroundColor $ColorScheme.Info

    $allMembers = @()
    $page = 1
    $perPage = 100
    $encodedGroup = [Uri]::EscapeDataString($Group)

    do {
        try {
            $uri = "$ServerUrl/groups/$encodedGroup/members/all?per_page=$perPage&page=$page"
            $response = Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop
            $allMembers += $response
            Write-Host "  Fetched page $page - $($response.Count) members" -ForegroundColor $ColorScheme.Dim
            $page++
        }
        catch {
            Write-Err "Failed to fetch group members: $_"
            return $null
        }
    } while ($response.Count -eq $perPage)

    Write-Success "Found $($allMembers.Count) total members in group '$Group'"
    return $allMembers
}

function Get-ProjectMembers {
    param(
        [string]$Project,
        [string]$ServerUrl,
        [hashtable]$Headers
    )

    Write-Host "`nFetching members of project '$Project'..." -ForegroundColor $ColorScheme.Info

    $allMembers = @()
    $page = 1
    $perPage = 100
    $encodedPath = [Uri]::EscapeDataString($Project)

    do {
        try {
            $uri = "$ServerUrl/projects/$encodedPath/members/all?per_page=$perPage&page=$page"
            $response = Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop
            $allMembers += $response
            Write-Host "  Fetched page $page - $($response.Count) members" -ForegroundColor $ColorScheme.Dim
            $page++
        }
        catch {
            Write-Err "Failed to fetch project members: $_"
            return $null
        }
    } while ($response.Count -eq $perPage)

    Write-Success "Found $($allMembers.Count) total members in project '$Project'"
    return $allMembers
}

function Get-MembershipDetails {
    param(
        [array]$Projects,
        [int]$UserId,
        [string]$Username,
        [string]$ServerUrl,
        [hashtable]$Headers
    )

    Write-Host "`nScanning projects for '$Username' (ID: $UserId) membership..." -ForegroundColor $ColorScheme.Info

    # Check PowerShell version for parallel support
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host "  Using parallel processing (PowerShell 7+, checking $($Projects.Count) projects concurrently)" -ForegroundColor $ColorScheme.Dim

        $memberships = $Projects | ForEach-Object -ThrottleLimit 20 -Parallel {
            $project = $_

            try {
                $uri = "$using:ServerUrl/projects/$($project.id)/members/all/$using:UserId"
                $member = Invoke-RestMethod -Uri $uri -Headers $using:Headers -ErrorAction Stop

                $accessLevelName = switch ($member.access_level) {
                    10 { "Guest" }
                    20 { "Reporter" }
                    30 { "Developer" }
                    40 { "Maintainer" }
                    50 { "Owner" }
                    default { "Unknown ($($member.access_level))" }
                }

                $expiryValue = if ($member.expires_at) { $member.expires_at } else { "NOT SET" }

                [PSCustomObject]@{
                    ProjectId       = $project.id
                    ProjectPath     = $project.path_with_namespace
                    ProjectName     = $project.name
                    AccessLevel     = $member.access_level
                    AccessLevelName = $accessLevelName
                    ExpiresAt       = $expiryValue
                }
            }
            catch {
                # Not a member, return nothing
            }
        }

        $memberships = @($memberships | Where-Object { $_ -ne $null })
    }
    else {
        # Use background jobs for PowerShell 5.1
        $maxConcurrent = 30
        Write-Host "  Using background jobs (PowerShell 5.1, checking projects with max $maxConcurrent concurrent jobs)" -ForegroundColor $ColorScheme.Dim

        $jobs = @()
        $jobCount = 0
        $total = $Projects.Count

        foreach ($project in $Projects) {
            while ((Get-Job -State Running).Count -ge $maxConcurrent) {
                Start-Sleep -Milliseconds 100
            }

            $jobs += Start-Job -ScriptBlock {
                param($projectId, $projectPath, $projectName, $userId, $serverUrl, $headers)

                try {
                    $uri = "$serverUrl/projects/$projectId/members/all/$userId"
                    $member = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop

                    $accessLevelName = switch ($member.access_level) {
                        10 { "Guest" }
                        20 { "Reporter" }
                        30 { "Developer" }
                        40 { "Maintainer" }
                        50 { "Owner" }
                        default { "Unknown ($($member.access_level))" }
                    }

                    $expiryValue = if ($member.expires_at) { $member.expires_at } else { "NOT SET" }

                    [PSCustomObject]@{
                        ProjectId       = $projectId
                        ProjectPath     = $projectPath
                        ProjectName     = $projectName
                        AccessLevel     = $member.access_level
                        AccessLevelName = $accessLevelName
                        ExpiresAt       = $expiryValue
                    }
                }
                catch {
                    # Not a member, return nothing
                }
            } -ArgumentList $project.id, $project.path_with_namespace, $project.name, $UserId, $ServerUrl, $Headers

            $jobCount++
            if ($jobCount % 50 -eq 0) {
                Write-Host "  Progress: Started $jobCount/$total jobs" -ForegroundColor $ColorScheme.Dim
            }
        }

        Write-Host "  Waiting for all jobs to complete..." -ForegroundColor $ColorScheme.Dim
        $results = $jobs | Wait-Job | Receive-Job
        $jobs | Remove-Job

        $memberships = @($results | Where-Object { $_ -ne $null })
    }

    Write-Success "Found $($memberships.Count) memberships for '$Username'"
    return $memberships
}

function Show-MemberList {
    param(
        [array]$Members,
        [string]$Title,
        [string]$Subtitle
    )

    Write-Header $Title
    Write-Host $Subtitle -ForegroundColor $ColorScheme.Info
    Write-Host "Total members: $($Members.Count)`n" -ForegroundColor $ColorScheme.Info

    $table = $Members | ForEach-Object {
        $accessLevelName = switch ($_.access_level) {
            10 { "Guest" }
            20 { "Reporter" }
            30 { "Developer" }
            40 { "Maintainer" }
            50 { "Owner" }
            default { "Unknown ($($_.access_level))" }
        }
        $expiryValue = if ($_.expires_at) { $_.expires_at } else { "NOT SET" }

        [PSCustomObject]@{
            UserId      = $_.id
            Username    = $_.username
            Name        = $_.name
            AccessLevel = $accessLevelName
            ExpiresAt   = $expiryValue
        }
    }

    $table | Format-Table UserId, Username, Name, AccessLevel, ExpiresAt -AutoSize

    Write-Host "`nSummary by Access Level:" -ForegroundColor $ColorScheme.Warning
    $table | Group-Object AccessLevel | Format-Table Name, Count -AutoSize

    Write-Host "Summary by Expiry Status:" -ForegroundColor $ColorScheme.Warning
    $withExpiry = ($table | Where-Object { $_.ExpiresAt -ne "NOT SET" }).Count
    $withoutExpiry = ($table | Where-Object { $_.ExpiresAt -eq "NOT SET" }).Count
    Write-Host "  With expiry set: $withExpiry" -ForegroundColor $ColorScheme.Success
    if ($withoutExpiry -gt 0) {
        Write-Host "  WITHOUT expiry: $withoutExpiry" -ForegroundColor $ColorScheme.Error
    }
}

function Set-MemberExpiry {
    param(
        [array]$Memberships,
        [int]$UserId,
        [string]$Username,
        [string]$ExpiryDate,
        [string]$ServerUrl,
        [hashtable]$Headers,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Header "DRY RUN - Setting Expiry Date: $ExpiryDate"
        Write-Host "[DRY RUN] No changes will be made." -ForegroundColor $ColorScheme.Warning
    }
    else {
        Write-Header "Setting Expiry Date: $ExpiryDate"
    }
    Write-Host "Member: $Username (ID: $UserId)" -ForegroundColor $ColorScheme.Info
    Write-Host "Projects to update: $($Memberships.Count)`n" -ForegroundColor $ColorScheme.Info

    if ($DryRun) {
        $preview = $Memberships | ForEach-Object {
            [PSCustomObject]@{
                ProjectId       = $_.ProjectId
                ProjectPath     = $_.ProjectPath
                AccessLevelName = $_.AccessLevelName
                CurrentExpiry   = $_.ExpiresAt
                NewExpiry       = $ExpiryDate
            }
        }

        Write-Host "Projects that would be updated:" -ForegroundColor $ColorScheme.Warning
        $preview | Format-Table ProjectId, ProjectPath, AccessLevelName, CurrentExpiry, NewExpiry -AutoSize
        Write-Warn "Dry run complete. Use without -DryRun to apply changes."
        return
    }

    $confirmation = Read-Host "Do you want to proceed? (yes/no)"
    if ($confirmation -ne "yes" -and $confirmation -ne "y") {
        Write-Warn "Operation cancelled by user"
        return
    }

    $results = @()
    $successCount = 0
    $failCount = 0

    foreach ($membership in $Memberships) {
        try {
            $headersWithContent = $Headers.Clone()
            $headersWithContent["Content-Type"] = "application/json"

            $putUri = "$ServerUrl/projects/$($membership.ProjectId)/members/$UserId"
            $putBody = @{
                access_level = $membership.AccessLevel
                expires_at   = $ExpiryDate
            } | ConvertTo-Json

            try {
                # Try PUT first (direct member update)
                $response = Invoke-RestMethod -Uri $putUri -Method Put -Headers $headersWithContent -Body $putBody -ErrorAction Stop
            }
            catch {
                # Fall back to POST (create direct membership for inherited members)
                $postUri = "$ServerUrl/projects/$($membership.ProjectId)/members"
                $postBody = @{
                    user_id      = $UserId
                    access_level = $membership.AccessLevel
                    expires_at   = $ExpiryDate
                } | ConvertTo-Json
                $response = Invoke-RestMethod -Uri $postUri -Method Post -Headers $headersWithContent -Body $postBody -ErrorAction Stop
            }

            $results += [PSCustomObject]@{
                ProjectId   = $membership.ProjectId
                ProjectPath = $membership.ProjectPath
                Status      = "Success"
                AccessLevel = $membership.AccessLevel
                ExpiresAt   = $response.expires_at
            }
            $successCount++
        }
        catch {
            $results += [PSCustomObject]@{
                ProjectId   = $membership.ProjectId
                ProjectPath = $membership.ProjectPath
                Status      = "Failed"
                AccessLevel = $membership.AccessLevel
                ExpiresAt   = $_.Exception.Message
            }
            $failCount++
        }
    }

    Write-Header "UPDATE RESULTS"
    Write-Host "Total projects: $($Memberships.Count)" -ForegroundColor $ColorScheme.Info
    Write-Success "Successful updates: $successCount"
    if ($failCount -gt 0) {
        Write-Err "Failed updates: $failCount"
    }

    Write-Host "`nDetailed results:" -ForegroundColor $ColorScheme.Warning
    $results | Format-Table ProjectId, ProjectPath, Status, AccessLevel, ExpiresAt -AutoSize
}

function Set-ProjectMemberExpiry {
    param(
        [string]$Project,
        [int]$UserId,
        [string]$Username,
        [string]$ExpiryDate,
        [string]$ServerUrl,
        [hashtable]$Headers,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Header "DRY RUN - Setting Expiry Date: $ExpiryDate"
        Write-Host "[DRY RUN] No changes will be made." -ForegroundColor $ColorScheme.Warning
    }
    else {
        Write-Header "Setting Expiry Date: $ExpiryDate"
    }
    Write-Host "Member  : $Username (ID: $UserId)" -ForegroundColor $ColorScheme.Info
    Write-Host "Project : $Project`n" -ForegroundColor $ColorScheme.Info

    try {
        $encodedPath = [Uri]::EscapeDataString($Project)

        # Get current membership to preserve access level (needed even for dry run to show current state)
        $current = Invoke-RestMethod -Uri "$ServerUrl/projects/$encodedPath/members/$UserId" -Headers $Headers -ErrorAction Stop

        $accessLevelName = switch ($current.access_level) {
            10 { "Guest" }
            20 { "Reporter" }
            30 { "Developer" }
            40 { "Maintainer" }
            50 { "Owner" }
            default { "Unknown ($($current.access_level))" }
        }
        $currentExpiry = if ($current.expires_at) { $current.expires_at } else { "NOT SET" }

        if ($DryRun) {
            Write-Host "Would update:" -ForegroundColor $ColorScheme.Warning
            Write-Host "  Access Level  : $accessLevelName ($($current.access_level))" -ForegroundColor $ColorScheme.Info
            Write-Host "  Current Expiry: $currentExpiry" -ForegroundColor $ColorScheme.Info
            Write-Host "  New Expiry    : $ExpiryDate" -ForegroundColor $ColorScheme.Info
            Write-Warn "Dry run complete. Use without -DryRun to apply changes."
            return
        }

        $confirmation = Read-Host "Do you want to proceed? (yes/no)"
        if ($confirmation -ne "yes" -and $confirmation -ne "y") {
            Write-Warn "Operation cancelled by user"
            return
        }

        $body = @{
            access_level = $current.access_level
            expires_at   = $ExpiryDate
        } | ConvertTo-Json

        $headersWithContent = $Headers.Clone()
        $headersWithContent["Content-Type"] = "application/json"

        $response = Invoke-RestMethod -Uri "$ServerUrl/projects/$encodedPath/members/$UserId" -Method Put -Headers $headersWithContent -Body $body -ErrorAction Stop

        Write-Header "UPDATE RESULT"
        Write-Success "Updated expiry for '$Username' in project '$Project'"
        Write-Host "  Access Level : $($current.access_level)" -ForegroundColor $ColorScheme.Info
        Write-Host "  Expires At   : $($response.expires_at)" -ForegroundColor $ColorScheme.Info
    }
    catch {
        Write-Err "Failed to update member: $_"
    }
}

function Get-GitLabDescendantGroups {
    param(
        [string]$Group,
        [string]$ServerUrl,
        [hashtable]$Headers
    )

    $allGroups = @()
    $page = 1
    $perPage = 100
    $encodedGroup = [Uri]::EscapeDataString($Group)

    do {
        try {
            $uri = "$ServerUrl/groups/$encodedGroup/descendant_groups?per_page=$perPage&page=$page"
            $response = Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop
            $allGroups += $response
            $page++
        }
        catch {
            Write-Err "Failed to fetch descendant groups: $_"
            return $null
        }
    } while ($response.Count -eq $perPage)

    return $allGroups
}

function Get-GroupMembershipDetails {
    param(
        [array]$Groups,
        [int]$UserId,
        [string]$Username,
        [string]$ServerUrl,
        [hashtable]$Headers
    )

    Write-Host "`nScanning $($Groups.Count) groups for '$Username' (ID: $UserId) direct group membership..." -ForegroundColor $ColorScheme.Info

    $memberships = @()
    foreach ($group in $Groups) {
        try {
            $uri = "$ServerUrl/groups/$($group.id)/members/$UserId"
            $member = Invoke-RestMethod -Uri $uri -Headers $Headers -ErrorAction Stop

            $accessLevelName = switch ($member.access_level) {
                10 { "Guest" }
                20 { "Reporter" }
                30 { "Developer" }
                40 { "Maintainer" }
                50 { "Owner" }
                default { "Unknown ($($member.access_level))" }
            }
            $expiryValue = if ($member.expires_at) { $member.expires_at } else { "NOT SET" }

            $memberships += [PSCustomObject]@{
                GroupId         = $group.id
                GroupPath       = $group.full_path
                GroupName       = $group.name
                AccessLevel     = $member.access_level
                AccessLevelName = $accessLevelName
                ExpiresAt       = $expiryValue
            }
        }
        catch {
            # Not a direct member of this group, skip
        }
    }

    Write-Success "Found $($memberships.Count) direct group memberships for '$Username'"
    return $memberships
}

function Remove-MemberFromGroups {
    param(
        [array]$GroupMemberships,
        [int]$UserId,
        [string]$Username,
        [string]$ServerUrl,
        [hashtable]$Headers,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Header "DRY RUN - Remove Member from Groups"
        Write-Host "[DRY RUN] No changes will be made." -ForegroundColor $ColorScheme.Warning
    }
    else {
        Write-Header "Remove Member from Groups"
    }
    Write-Host "Member: $Username (ID: $UserId)" -ForegroundColor $ColorScheme.Info
    Write-Host "Groups to remove from: $($GroupMemberships.Count)`n" -ForegroundColor $ColorScheme.Info

    $preview = $GroupMemberships | ForEach-Object {
        [PSCustomObject]@{
            GroupId         = $_.GroupId
            GroupPath       = $_.GroupPath
            AccessLevelName = $_.AccessLevelName
            ExpiresAt       = $_.ExpiresAt
        }
    }

    if ($DryRun) {
        Write-Host "Groups that would be removed from:" -ForegroundColor $ColorScheme.Warning
        $preview | Format-Table GroupId, GroupPath, AccessLevelName, ExpiresAt -AutoSize
        Write-Warn "Dry run complete. Use without -DryRun to apply changes."
        return
    }

    Write-Host "Groups that will be removed from:" -ForegroundColor $ColorScheme.Warning
    $preview | Format-Table GroupId, GroupPath, AccessLevelName, ExpiresAt -AutoSize

    $confirmation = Read-Host "Do you want to proceed? (yes/no)"
    if ($confirmation -ne "yes" -and $confirmation -ne "y") {
        Write-Warn "Operation cancelled by user"
        return
    }

    $results = @()
    $successCount = 0
    $failCount = 0

    foreach ($gm in $GroupMemberships) {
        try {
            Invoke-RestMethod -Uri "$ServerUrl/groups/$($gm.GroupId)/members/$UserId" -Method Delete -Headers $Headers -ErrorAction Stop

            $results += [PSCustomObject]@{
                GroupId   = $gm.GroupId
                GroupPath = $gm.GroupPath
                Status    = "Removed"
            }
            $successCount++
        }
        catch {
            $results += [PSCustomObject]@{
                GroupId   = $gm.GroupId
                GroupPath = $gm.GroupPath
                Status    = "Failed: $($_.Exception.Message)"
            }
            $failCount++
        }
    }

    Write-Header "REMOVE RESULTS"
    Write-Host "Total groups: $($GroupMemberships.Count)" -ForegroundColor $ColorScheme.Info
    Write-Success "Successfully removed: $successCount"
    if ($failCount -gt 0) {
        Write-Err "Failed: $failCount"
    }

    Write-Host "`nDetailed results:" -ForegroundColor $ColorScheme.Warning
    $results | Format-Table GroupId, GroupPath, Status -AutoSize
}

function Remove-ProjectMember {
    param(
        [string]$Project,
        [int]$UserId,
        [string]$Username,
        [string]$ServerUrl,
        [hashtable]$Headers,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Header "DRY RUN - Remove Member from Project"
        Write-Host "[DRY RUN] No changes will be made." -ForegroundColor $ColorScheme.Warning
    }
    else {
        Write-Header "Remove Member from Project"
    }
    Write-Host "Member  : $Username (ID: $UserId)" -ForegroundColor $ColorScheme.Info
    Write-Host "Project : $Project`n" -ForegroundColor $ColorScheme.Info

    try {
        $encodedPath = [Uri]::EscapeDataString($Project)

        # Fetch current membership to confirm the user is actually a direct member
        try {
            $current = Invoke-RestMethod -Uri "$ServerUrl/projects/$encodedPath/members/$UserId" -Headers $Headers -ErrorAction Stop
        }
        catch {
            Write-Err "User '$Username' is not a direct member of project '$Project' (or not found)"
            return
        }

        $accessLevelName = switch ($current.access_level) {
            10 { "Guest" }
            20 { "Reporter" }
            30 { "Developer" }
            40 { "Maintainer" }
            50 { "Owner" }
            default { "Unknown ($($current.access_level))" }
        }
        $currentExpiry = if ($current.expires_at) { $current.expires_at } else { "NOT SET" }

        Write-Host "Current membership:" -ForegroundColor $ColorScheme.Warning
        Write-Host "  Access Level  : $accessLevelName ($($current.access_level))" -ForegroundColor $ColorScheme.Info
        Write-Host "  Expires At    : $currentExpiry" -ForegroundColor $ColorScheme.Info

        if ($DryRun) {
            Write-Host "`nWould remove '$Username' from project '$Project'." -ForegroundColor $ColorScheme.Warning
            Write-Warn "Dry run complete. Use without -DryRun to apply changes."
            return
        }

        $confirmation = Read-Host "`nDo you want to proceed? (yes/no)"
        if ($confirmation -ne "yes" -and $confirmation -ne "y") {
            Write-Warn "Operation cancelled by user"
            return
        }

        Invoke-RestMethod -Uri "$ServerUrl/projects/$encodedPath/members/$UserId" -Method Delete -Headers $Headers -ErrorAction Stop

        Write-Header "REMOVE RESULT"
        Write-Success "Removed '$Username' from project '$Project'"
    }
    catch {
        Write-Err "Failed to remove member: $_"
    }
}

function Remove-MemberFromGroup {
    param(
        [array]$Memberships,
        [int]$UserId,
        [string]$Username,
        [string]$ServerUrl,
        [hashtable]$Headers,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Header "DRY RUN - Remove Member from Group Projects"
        Write-Host "[DRY RUN] No changes will be made." -ForegroundColor $ColorScheme.Warning
    }
    else {
        Write-Header "Remove Member from Group Projects"
    }
    Write-Host "Member: $Username (ID: $UserId)" -ForegroundColor $ColorScheme.Info
    Write-Host "Projects to remove from: $($Memberships.Count)`n" -ForegroundColor $ColorScheme.Info

    $preview = $Memberships | ForEach-Object {
        [PSCustomObject]@{
            ProjectId       = $_.ProjectId
            ProjectPath     = $_.ProjectPath
            AccessLevelName = $_.AccessLevelName
            ExpiresAt       = $_.ExpiresAt
        }
    }

    if ($DryRun) {
        Write-Host "Projects that would be removed from:" -ForegroundColor $ColorScheme.Warning
        $preview | Format-Table ProjectId, ProjectPath, AccessLevelName, ExpiresAt -AutoSize
        Write-Warn "Dry run complete. Use without -DryRun to apply changes."
        return
    }

    Write-Host "Projects that will be removed from:" -ForegroundColor $ColorScheme.Warning
    $preview | Format-Table ProjectId, ProjectPath, AccessLevelName, ExpiresAt -AutoSize

    $confirmation = Read-Host "Do you want to proceed? (yes/no)"
    if ($confirmation -ne "yes" -and $confirmation -ne "y") {
        Write-Warn "Operation cancelled by user"
        return
    }

    $results = @()
    $successCount = 0
    $failCount = 0

    foreach ($membership in $Memberships) {
        try {
            Invoke-RestMethod -Uri "$ServerUrl/projects/$($membership.ProjectId)/members/$UserId" -Method Delete -Headers $Headers -ErrorAction Stop

            $results += [PSCustomObject]@{
                ProjectId   = $membership.ProjectId
                ProjectPath = $membership.ProjectPath
                Status      = "Removed"
            }
            $successCount++
        }
        catch {
            $results += [PSCustomObject]@{
                ProjectId   = $membership.ProjectId
                ProjectPath = $membership.ProjectPath
                Status      = "Failed: $($_.Exception.Message)"
            }
            $failCount++
        }
    }

    Write-Header "REMOVE RESULTS"
    Write-Host "Total projects: $($Memberships.Count)" -ForegroundColor $ColorScheme.Info
    Write-Success "Successfully removed: $successCount"
    if ($failCount -gt 0) {
        Write-Err "Failed: $failCount"
    }

    Write-Host "`nDetailed results:" -ForegroundColor $ColorScheme.Warning
    $results | Format-Table ProjectId, ProjectPath, Status -AutoSize
}

# ============================================================================
# Main Script Execution
# ============================================================================

try {
    $headers = @{
        "PRIVATE-TOKEN" = $PrivateToken
    }

    Write-Header "GitLab Member Management CLI"
    Write-Host "Operation: $Operation" -ForegroundColor $ColorScheme.Info
    if ($DryRun) {
        Write-Host "Mode     : DRY RUN (no changes will be made)" -ForegroundColor $ColorScheme.Warning
    }

    # Validate: must provide -Group or -Project
    if (-not $Group -and -not $Project) {
        Write-Err "Either -Group or -Project must be specified"
        exit 1
    }
    if ($Group -and $Project) {
        Write-Err "-Group and -Project cannot be used together"
        exit 1
    }

    # -------------------------------------------------------------------------
    # Project-scoped operations
    # -------------------------------------------------------------------------
    if ($Project) {
        Write-Host "Project: $Project" -ForegroundColor $ColorScheme.Info

        $projectInfo = Get-GitLabProject -Project $Project -ServerUrl $ServerUrl -Headers $headers
        if (-not $projectInfo) { exit 1 }

        $projectLabel = "Project: $($projectInfo.path_with_namespace) (ID: $($projectInfo.id))"

        if ($Operation -eq "list") {
            $members = Get-ProjectMembers -Project $Project -ServerUrl $ServerUrl -Headers $headers
            if (-not $members) { exit 1 }
            if ($members.Count -eq 0) {
                Write-Warn "No members found in project '$Project'"
                exit 0
            }
            Show-MemberList -Members $members -Title "PROJECT MEMBER LIST" -Subtitle $projectLabel
        }
        elseif ($Operation -eq "set-expiry") {
            if (-not $ExpiryDate) {
                Write-Err "-ExpiryDate is required for 'set-expiry' operation"
                exit 1
            }
            if (-not $MemberUsername -and -not $MemberId) {
                Write-Err "Either -MemberUsername or -MemberId must be specified for 'set-expiry'"
                exit 1
            }

            try {
                $parsedDate = [DateTime]::ParseExact($ExpiryDate, "yyyy-MM-dd", $null)
                Write-Host "Expiry date: $($parsedDate.ToString('dddd, MMMM dd, yyyy'))" -ForegroundColor $ColorScheme.Info
            }
            catch {
                Write-Err "Invalid date format. Use YYYY-MM-DD (e.g., 2026-04-15)"
                exit 1
            }

            $userId = $MemberId
            $username = $MemberUsername

            if ($MemberUsername -and -not $MemberId) {
                Write-Host "`nResolving user '$MemberUsername'..." -ForegroundColor $ColorScheme.Info
                $user = Get-GitLabUser -Username $MemberUsername -ServerUrl $ServerUrl -Headers $headers
                if (-not $user) { exit 1 }
                $userId = $user.id
                $username = $user.username
                Write-Success "Found user: '$($user.name)' (ID: $userId, Username: '$username')"
            }
            elseif ($MemberId -and -not $MemberUsername) {
                $username = "User#$MemberId"
            }

            Set-ProjectMemberExpiry -Project $Project -UserId $userId -Username $username -ExpiryDate $ExpiryDate -ServerUrl $ServerUrl -Headers $headers -DryRun:$DryRun
        }
        elseif ($Operation -eq "remove") {
            if (-not $MemberUsername -and -not $MemberId) {
                Write-Err "Either -MemberUsername or -MemberId must be specified for 'remove'"
                exit 1
            }

            $userId = $MemberId
            $username = $MemberUsername

            if ($MemberUsername -and -not $MemberId) {
                Write-Host "`nResolving user '$MemberUsername'..." -ForegroundColor $ColorScheme.Info
                $user = Get-GitLabUser -Username $MemberUsername -ServerUrl $ServerUrl -Headers $headers
                if (-not $user) { exit 1 }
                $userId = $user.id
                $username = $user.username
                Write-Success "Found user: '$($user.name)' (ID: $userId, Username: '$username')"
            }
            elseif ($MemberId -and -not $MemberUsername) {
                $username = "User#$MemberId"
            }

            Remove-ProjectMember -Project $Project -UserId $userId -Username $username -ServerUrl $ServerUrl -Headers $headers -DryRun:$DryRun
        }

        Write-Host ""
        Write-Success "Operation completed successfully"
        exit 0
    }

    # -------------------------------------------------------------------------
    # Group-scoped operations
    # -------------------------------------------------------------------------
    Write-Host "Group: $Group" -ForegroundColor $ColorScheme.Info

    $hasUserParam = $MemberUsername -or $MemberId

    # List group members (no user filter)
    if ($Operation -eq "list" -and -not $hasUserParam) {
        $groupInfo = Get-GitLabGroup -Group $Group -ServerUrl $ServerUrl -Headers $headers
        if (-not $groupInfo) { exit 1 }
        $members = Get-GroupMembers -Group $Group -ServerUrl $ServerUrl -Headers $headers
        if (-not $members) { exit 1 }
        if ($members.Count -eq 0) {
            Write-Warn "No members found in group '$Group'"
            exit 0
        }
        $subtitle = "Group: $($groupInfo.full_path) (ID: $($groupInfo.id))"
        Show-MemberList -Members $members -Title "GROUP MEMBER LIST" -Subtitle $subtitle
        Write-Host ""
        Write-Success "Operation completed successfully"
        exit 0
    }

    # User-scoped operations within a group
    if (-not $hasUserParam) {
        Write-Err "Either -MemberUsername or -MemberId must be specified for '$Operation'"
        exit 1
    }

    if ($Operation -eq "set-expiry" -and -not $ExpiryDate) {
        Write-Err "-ExpiryDate is required for 'set-expiry' operation"
        exit 1
    }

    # Resolve user
    $userId = $MemberId
    $username = $MemberUsername

    if ($MemberUsername -and -not $MemberId) {
        Write-Host "`nResolving user '$MemberUsername'..." -ForegroundColor $ColorScheme.Info
        $user = Get-GitLabUser -Username $MemberUsername -ServerUrl $ServerUrl -Headers $headers
        if (-not $user) { exit 1 }
        $userId = $user.id
        $username = $user.username
        Write-Success "Found user: '$($user.name)' (ID: $userId, Username: '$username')"
    }
    elseif ($MemberId -and -not $MemberUsername) {
        $username = "User#$MemberId"
    }

    # Fetch all projects in group
    $projects = Get-GitLabProjects -Group $Group -ServerUrl $ServerUrl -IgnoreSubgroups $IgnoreSubgroups -Headers $headers
    if (-not $projects) { exit 1 }

    # Scan memberships
    $memberships = Get-MembershipDetails -Projects $projects -UserId $userId -Username $username -ServerUrl $ServerUrl -Headers $headers

    if ($memberships.Count -eq 0) {
        Write-Warn "No memberships found for '$username' in group '$Group'"
        exit 0
    }

    switch ($Operation) {
        "list" {
            Write-Header "MEMBERSHIP LIST"
            Write-Host "Member: $username (ID: $userId)" -ForegroundColor $ColorScheme.Info
            Write-Host "Total memberships: $($memberships.Count)`n" -ForegroundColor $ColorScheme.Info

            $memberships | Format-Table ProjectId, ProjectPath, AccessLevelName, ExpiresAt -AutoSize

            Write-Host "`nSummary by Access Level:" -ForegroundColor $ColorScheme.Warning
            $memberships | Group-Object AccessLevelName | Format-Table Name, Count -AutoSize

            Write-Host "Summary by Expiry Status:" -ForegroundColor $ColorScheme.Warning
            $withExpiry = ($memberships | Where-Object { $_.ExpiresAt -ne "NOT SET" }).Count
            $withoutExpiry = ($memberships | Where-Object { $_.ExpiresAt -eq "NOT SET" }).Count
            Write-Host "  With expiry set: $withExpiry" -ForegroundColor $ColorScheme.Success
            if ($withoutExpiry -gt 0) {
                Write-Host "  WITHOUT expiry: $withoutExpiry" -ForegroundColor $ColorScheme.Error
            }
        }

        "set-expiry" {
            try {
                $parsedDate = [DateTime]::ParseExact($ExpiryDate, "yyyy-MM-dd", $null)
                Write-Host "Expiry date: $($parsedDate.ToString('dddd, MMMM dd, yyyy'))" -ForegroundColor $ColorScheme.Info
            }
            catch {
                Write-Err "Invalid date format. Use YYYY-MM-DD (e.g., 2026-03-31)"
                exit 1
            }

            $membershipsToUpdate = $memberships | Where-Object {
                $_.ExpiresAt -eq "NOT SET" -or $_.ExpiresAt -ne $ExpiryDate
            }

            $alreadySet = $memberships.Count - $membershipsToUpdate.Count
            if ($alreadySet -gt 0) {
                Write-Host "`n$alreadySet memberships already have expiry date set to $ExpiryDate (skipped)" -ForegroundColor $ColorScheme.Info
            }

            if ($membershipsToUpdate.Count -eq 0) {
                Write-Success "All memberships already have the correct expiry date. Nothing to update."
            }
            else {
                Set-MemberExpiry -Memberships $membershipsToUpdate -UserId $userId -Username $username -ExpiryDate $ExpiryDate -ServerUrl $ServerUrl -Headers $headers -DryRun:$DryRun
            }
        }

        "remove" {
            # Scan for direct group memberships — required because inherited project
            # access cannot be removed at the project level (DELETE returns 404).
            $rootGroupInfo = Get-GitLabGroup -Group $Group -ServerUrl $ServerUrl -Headers $headers
            $allGroupsToScan = @()
            if ($rootGroupInfo) {
                $allGroupsToScan += [PSCustomObject]@{ id = $rootGroupInfo.id; full_path = $rootGroupInfo.full_path; name = $rootGroupInfo.name }
            }
            $descendantGroups = Get-GitLabDescendantGroups -Group $Group -ServerUrl $ServerUrl -Headers $headers
            if ($descendantGroups) { $allGroupsToScan += $descendantGroups }

            $groupMemberships = Get-GroupMembershipDetails -Groups $allGroupsToScan -UserId $userId -Username $username -ServerUrl $ServerUrl -Headers $headers

            if ($groupMemberships.Count -gt 0) {
                # Remove at group level — this cascades and revokes inherited project access.
                if ($memberships.Count -gt 0) {
                    Write-Host "`nNote: $($memberships.Count) project memberships are inherited from group access and will be revoked automatically." -ForegroundColor $ColorScheme.Dim
                }
                Remove-MemberFromGroups -GroupMemberships $groupMemberships -UserId $userId -Username $username -ServerUrl $ServerUrl -Headers $headers -DryRun:$DryRun
            }
            else {
                # No group memberships — fall back to project-level removal.
                Remove-MemberFromGroup -Memberships $memberships -UserId $userId -Username $username -ServerUrl $ServerUrl -Headers $headers -DryRun:$DryRun
            }
        }
    }

    Write-Host ""
    Write-Success "Operation completed successfully"

}
catch {
    Write-Err "An unexpected error occurred: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor $ColorScheme.Dim
    exit 1
}
