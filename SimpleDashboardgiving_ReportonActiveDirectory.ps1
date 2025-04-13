﻿# Run in elevated PowerShell

# --- Install Required Modules ---
Install-Module -Name Dashimo -Force -Scope CurrentUser
Install-Module -Name TheDashboard -Force -Scope CurrentUser

# --- Import Modules ---
Import-Module Dashimo
Import-Module PSWriteHTML

# --- Prepare Folder Structure ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportsRoot = "$PSScriptRoot\Reports"
$Folders = @("ActiveDirectory", "GroupPolicies", "DomainControllers")

foreach ($folder in $Folders) {
    $path = Join-Path $ReportsRoot $folder
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}


# --- Launch the Dashboard ---
Start-TheDashboard -HTMLPath "$ReportsRoot\Index.html" -Logo 'https://www.newyorker.com/news/daily-comment/the-agony-and-ecstasy-of-argentinas-world-cup-victory' -ShowHTML {
    # Gages
    $Today = Get-Date
    $Forest = Get-ADForest
    $AllUsers = $Forest.Domains | ForEach-Object { Get-ADUser -Filter * -Properties 'DistinguishedName' -Server $_ }
    $AllComputers = $Forest.Domains | ForEach-Object { Get-ADComputer -Filter * -Properties 'DistinguishedName' -Server $_ }
    $AllGroups = $Forest.Domains | ForEach-Object { Get-ADGroup -Filter * -Server $_ }
    $AllGroupPolicies = $Forest.Domains | ForEach-Object { Get-GPO -All -Domain $_ }

    New-DashboardGage -Label 'Users' -MinValue 0 -MaxValue 500 -Value $AllUsers.Count -Date $Today
    New-DashboardGage -Label 'Computers' -MinValue 0 -MaxValue 200 -Value $AllComputers.Count -Date $Today
    New-DashboardGage -Label 'Groups' -MinValue 0 -MaxValue 200 -Value $AllGroups.Count -Date $Today
    New-DashboardGage -Label 'Group Policies' -MinValue 0 -MaxValue 200 -Value $AllGroupPolicies.Count -Date $Today

    # Tabs linking to each folder
    New-DashboardFolder -Name 'ActiveDirectory' -IconBrands gofore -UrlName 'ActiveDirectory' -Path "$ReportsRoot\ActiveDirectory"
    New-DashboardFolder -Name 'GroupPolicies' -IconBrands android -UrlName 'GPO' -Path "$ReportsRoot\GroupPolicies"
    New-DashboardFolder -Name 'DomainControllers' -IconBrands android -UrlName 'DomainControllers' -Path "$ReportsRoot\DomainControllers"

    # Replacements for file name prettifying
    New-DashboardReplacement -SplitOn "_" -AddSpaceToName
    New-DashboardReplacement -BeforeSplit @{
        'GPOZaurr'         = ''
        'PingCastle-'      = ''
        'Testimo'          = ''
        'GroupMembership-' = ''
        '_Regional'        = ' Regional'
    }
    New-DashboardReplacement -AfterSplit @{
        'G P O'     = 'GPO'
        'L A P S'   = 'LAPS'
        'L D A P'   = 'LDAP'
        'K R B G T' = 'KRBGT'
        'I N S'     = 'INS'
        'I T R X X' = 'ITRXX'
        'A D'       = 'AD'
        'D H C P'   = 'DHCP'
        'D F S'     = 'DFS'
        'D C'       = 'DC'
    }

    New-DashboardLimit -LimitItem 1 -IncludeHistory
} -StatisticsPath "$PSScriptRoot\Dashboard.xml" -Verbose -Online
