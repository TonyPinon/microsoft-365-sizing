<#
.SYNOPSIS
    Parse-Rubrik365SizingReports.ps1 returns statistics on number of accounts, sites and how much storage they are using in a Micosoft 365 Tenant
.DESCRIPTION
    Parse-Rubrik365SizingReports.ps1 returns statistics on number of accounts, sites and how much storage they are using in a Micosoft 365 Tenant
    Before running the script, it is expected that you have manually pulled the reports from the customer's Microsoft 365 Tenant. 

    You should only be running script IF you could not run Get-RubrikM365SizingInfo.ps1. This is a backup script if you have to run things manually. 

.EXAMPLE
    PS C:\> .\Parse-Rubrik365SizingReports.ps1
    Will look for files named simialrly to the below, process the data and output a sizing document for you to use. 
        MailboxUsageStorage9_13_2021 7_08_49 PM.csv
        MailboxUsageDetail9_13_2021 7_08_50 PM.csv
        OneDriveUsageAccountDetail9_13_2021 7_37_00 PM.csv
        OneDriveUsageStorage9_13_2021 7_09_43 PM.csv
        Office365ActiveUserDetail9_13_2021 7_09_22 PM.csv
        SharePointSiteUsageDetail9_13_2021 7_10_30 PM.csv
        SharePointSiteUsageStorage9_13_2021 7_10_28 PM.csv
.INPUTS
    Inputs (if any)
.OUTPUTS
    RubrikM365Sizing.txt containing the below data. 
    Exchange

    Name                         Value
    ----                         -----
    NumberOfUsers                296
    TotalSizeGB                  1.26
    SizePerUserGB                0
    AverageGrowthPercentage      8
    OneYearStorageForecastInGB   1.3608
    ThreeYearStorageForecastInGB 1.5624

    ==========================================================================
    OneDrive

    Name                         Value
    ----                         -----
    NumberOfUsers                308
    TotalSizeGB                  3139.39
    SizePerUserGB                10.19
    AverageGrowthPercentage      912
    OneYearStorageForecastInGB   31770.6268
    ThreeYearStorageForecastInGB 89033.1004

    ==========================================================================
    Sharepoint

    Name                         Value
    ----                         -----
    NumberOfSites                17
    TotalSizeGB                  4.24
    SizePerUserGB                0.25
    AverageGrowthPercentage      15
    OneYearStorageForecastInGB   4.876
    ThreeYearStorageForecastInGB 6.148

    ==========================================================================
    Licensing

    Name                         Value
    ----                         -----
    MICROSOFT 365 BUSINESS BASIC 296

    ==========================================================================
    TotalRubrikStorageNeeded

    Name          Value
    ----          -----
    OneYearInGB   31776.8636
    ThreeYearInGB 89040.8108

    ==========================================================================

    We will also output an object with the above information that can be used for further integration.
.NOTES
    Author:         Chris Lumnah
    Created Date:   9/13/2013
#>
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Reports
[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet("7","30","90","180")]
    [string]$Period = '180',
    # Parameter help description
    [Parameter()]
    [Switch]
    $OutputObject
)

# Provide OS agnostic temp folder path for raw reports
$systemTempFolder = [System.IO.Path]::GetTempPath()

function Measure-AverageGrowth {
    param (
        [Parameter(Mandatory)]
        [string]$ReportCSV, 
        [Parameter(Mandatory)]
        [string]$ReportName

    )
    if ($ReportName -eq 'getOneDriveUsageStorage'){
        $UsageReport = Import-Csv -Path $ReportCSV | Where-Object {$_.'Site Type' -eq 'OneDrive'} |Sort-Object -Property "Report Date"
    }else{
        $UsageReport = Import-Csv -Path $ReportCSV | Sort-Object -Property "Report Date"
    }
    
    $Record = 1
    $StorageUsage = @()
    foreach ($item in $UsageReport) {
        if ($Record -eq 1){
            $StorageUsed = $Item."Storage Used (Byte)"
        }else {
            $StorageUsage += (
                New-Object psobject -Property @{
                    Growth =  [math]::Round(((($Item.'Storage Used (Byte)' / $StorageUsed) -1) * 100),2)
                }
            )
            $StorageUsed = $Item."Storage Used (Byte)"
        }
        $Record = $Record + 1
    }
    
    $AverageGrowth = ($StorageUsage | Measure-Object -Property Growth -Average).Average
    # AverageGrowth is based on 180 days. This is not annual growth. To provide an annual growth we will take the value of AverageGrowth * 2 and then round up to the nearest whole percentage. While this is not exact, it should be close enough for our purposes.
    $AverageGrowth = [math]::Ceiling(($AverageGrowth * 2)) 
    return $AverageGrowth
}
function ProcessUsageReport {
    param (
        [Parameter(Mandatory)]
        [string]$ReportCSV, 
        [Parameter(Mandatory)]
        [string]$ReportName,
        [Parameter(Mandatory)]
        [string]$Section
    )

    $ReportDetail = Import-Csv -Path $ReportCSV | Where-Object {$_.'Is Deleted' -eq 'FALSE'}
    $SummarizedData = $ReportDetail | Measure-Object -Property 'Storage Used (Byte)' -Sum -Average
    switch ($Section) {
        'Sharepoint' { $M365Sizing.$($Section).NumberOfSites = $SummarizedData.Count }
        Default {$M365Sizing.$($Section).NumberOfUsers = $SummarizedData.Count}
    }
    $M365Sizing.$($Section).TotalSizeGB = [math]::Round(($SummarizedData.Sum / 1GB), 2, [MidPointRounding]::AwayFromZero)
    $M365Sizing.$($Section).SizePerUserGB = [math]::Round((($SummarizedData.Average) / 1GB), 2)
}

# Connect-MgGraph -Scopes @( )


$M365Sizing = [ordered]@{
    Exchange = [ordered]@{
        NumberOfUsers = 0
        TotalSizeGB   = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
        OneYearStorageForecastInGB = 0
        ThreeYearStorageForecastInGB = 0
    }
    OneDrive = [ordered]@{
        NumberOfUsers = 0
        TotalSizeGB   = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
        OneYearStorageForecastInGB = 0
        ThreeYearStorageForecastInGB = 0
    }
    Sharepoint = [ordered]@{
        NumberOfSites = 0
        TotalSizeGB   = 0
        SizePerUserGB = 0
        AverageGrowthPercentage = 0
        OneYearStorageForecastInGB = 0
        ThreeYearStorageForecastInGB = 0
    }
    Licensing = [ordered]@{
        # Commented out for now, but we can get the number of licensed users if required (Not just activated).
        # Exchange         = 0
        # OneDrive         = 0
        # SharePoint       = 0
        # Teams            = 0
    }
    TotalRubrikStorageNeeded = [ordered]@{
        OneYearInGB = 0
        ThreeYearInGB   = 0
    }
    # Skype = @{
    #     NumberOfUsers = 0
    #     TotalSizeGB = 0
    #     SizePerUserGB = 0
    #     AverageGrowthPercentage = 0
    # }
    # Yammer = @{
    #     NumberOfUsers = 0
    #     TotalSizeGB = 0
    #     SizePerUserGB = 0
    #     AverageGrowthPercentage = 0
    # }
    # Teams = @{
    #     NumberOfUsers = 0
    #     TotalSizeGB = 0
    #     SizePerUserGB = 0
    #     AverageGrowthPercentage = 0
    # }
}


#region Usage Detail Reports
# Run Usage Detail Reports for different sections to get counts, total size of each section and average size. 
# We will only capture data that [Is Deleted] is equal to false. If [Is Deleted] is equal to True then that account has been deleted 
# from the customers M365 Tenant. It should not be counted in the sizing reports as We will not backup those objects. 
$UsageDetailReports = @{}
$UsageDetailReports.Add('Exchange', 'getMailboxUsageDetail')
$UsageDetailReports.Add('OneDrive', 'getOneDriveUsageAccountDetail')
$UsageDetailReports.Add('Sharepoint', 'getSharePointSiteUsageDetail')
foreach($Section in $UsageDetailReports.Keys){
    switch ($Section) {
        'Exchange' {$ReportCSV = Get-ChildItem -Path .\ -Filter "MailboxUsageDetail*.csv"}
        'OneDrive' {$ReportCSV = Get-ChildItem -Path .\ -Filter "OneDriveUsageAccountDetail*.csv"}
        'Sharepoint' {$ReportCSV = Get-ChildItem -Path .\ -Filter "SharePointSiteUsageDetail*.csv"}
    }
    ProcessUsageReport -ReportCSV $ReportCSV -ReportName $UsageDetailReports[$Section] -Section $Section
}
#endregion


#region Storage Usage Reports
# Run Storage Usage Reports for each section get get a trend of storage used for the period provided. We will get the growth percentage
# for each day and then average them all across the period provided. This way we can take into account the growth or the reduction 
# of storage used across the entire period. 
$StorageUsageReports = @{}
$StorageUsageReports.Add('Exchange', 'getMailboxUsageStorage')
$StorageUsageReports.Add('OneDrive', 'getOneDriveUsageStorage')
$StorageUsageReports.Add('Sharepoint', 'getSharePointSiteUsageStorage')
foreach($Section in $StorageUsageReports.Keys){
    switch ($Section) {
        'Exchange' {$ReportCSV = Get-ChildItem -Path .\ -Filter "MailboxUsageStorage*.csv"}
        'OneDrive' {$ReportCSV = Get-ChildItem -Path .\ -Filter "OneDriveUsageStorage*.csv"}
        'Sharepoint' {$ReportCSV = Get-ChildItem -Path .\ -Filter "SharePointSiteUsageStorage*.csv"}
    }
    $AverageGrowth = Measure-AverageGrowth -ReportCSV $ReportCSV -ReportName $StorageUsageReports[$Section]
    $M365Sizing.$($Section).AverageGrowthPercentage = [math]::Round($AverageGrowth,2)
}
#endregion



#region License usage
$licenseReportPath = Get-ChildItem -Path .\ -Filter "Office365ActiveUserDetail*.csv"
$licenseReport = Import-Csv -Path $licenseReportPath | Where-Object 'is deleted' -eq 'FALSE'

$licensesToIgnore = "POWER APPS PER USER PLAN","DYNAMICS 365 REMOTE ASSIST","POWER AUTOMATE PER USER PLAN","BUSINESS APPS (FREE)","MICROSOFT BUSINESS CENTER","DYNAMICS 365 GUIDES","POWERAPPS PER APP BASELINE","MICROSOFT MYANALYTICS","MICROSOFT 365 PHONE SYSTEM","POWER BI PRO","AZURE ACTIVE DIRECTORY PREMIUM","MICROSOFT INTUNE","DYNAMICS 365 TEAM MEMBERS","SECURITY E3","ENTERPRISE MOBILITY","MICROSOFT WORKPLACE ANALYTICS","MICROSOFT POWER AUTOMATE FREE","MICROSOFT TEAMS EXPLORATORY","MICROSOFT STREAM TRIAL", "VISIO PLAN 2","MICROSOFT POWER APPS PLAN 2 TRIAL","DYNAMICS 365 CUSTOMER ENGAGEMENT PLAN","DYNAMICS 365 BUSINESS CENTRAL ESSENTIAL","PROJECT PLAN","DYNAMICS 365 BUSINESS CENTRAL FOR IWS","PROJECT ONLINE ESSENTIALS","MICROSOFT TEAMS TRIAL","POWERAPPS AND LOGIC FLOWS","DYNAMICS 365 CUSTOMER VOICE TRIAL","MICROSOFT DEFENDER FOR ENDPOINT","DYNAMICS 365 SALES PREMIUM VIRAL TRIAL","DYNAMICS 365 P1 TRIAL FOR INFORMATION WORKERS","POWER BI (FREE)",""

$assignedProducts = $licenseReport | ForEach-Object {$_.'Assigned Products'.Split('+')} | Group-Object | Select-Object Name,Count

$assignedProducts | ForEach-Object {if ($_.name -NotIn $licensesToIgnore) {$M365Sizing.Licensing.Add($_.name, $_.count)}}

# We can add these back in if we want total licensed users for each feature.
# $M365Sizing.Licensing.Exchange   = ($licenseReport | Where-Object 'Has Exchange License' -eq 'True' | measure-object).Count
# $M365Sizing.Licensing.OneDrive   = ($licenseReport | Where-Object 'Has OneDrive License' -eq 'True' | measure-object).Count
# $M365Sizing.Licensing.SharePoint = ($licenseReport | Where-Object 'Has Sharepoint License' -eq 'True' | measure-object).Count
# $M365Sizing.Licensing.Teams      = ($licenseReport | Where-Object 'Has Teams License' -eq 'True' | measure-object).Count
#endregion

foreach($Section in $M365Sizing | Select-Object -ExpandProperty Keys){

    if ( $Section -NotIn @("Licensing", "TotalRubrikStorageNeeded") )
    {
        $M365Sizing.$($Section).OneYearStorageForecastInGB = $M365Sizing.$($Section).TotalSizeGB * (1.0 + (($M365Sizing.$($Section).AverageGrowthPercentage / 100) * 1))
        $M365Sizing.$($Section).ThreeYearStorageForecastInGB = $M365Sizing.$($Section).TotalSizeGB * (1.0 + (($M365Sizing.$($Section).AverageGrowthPercentage / 100) * 3))
    
        $M365Sizing.TotalRubrikStorageNeeded.OneYearInGB = $M365Sizing.TotalRubrikStorageNeeded.OneYearInGB + $M365Sizing.$($Section).OneYearStorageForecastInGB
        $M365Sizing.TotalRubrikStorageNeeded.ThreeYearInGB = $M365Sizing.TotalRubrikStorageNeeded.ThreeYearInGB + $M365Sizing.$($Section).ThreeYearStorageForecastInGB
    }

    

    Write-Output $Section | Out-File -FilePath .\RubrikMS365Sizing.txt -Append
    Write-Output $M365Sizing.$($Section) |Format-Table -AutoSize | Out-File -FilePath .\RubrikMS365Sizing.txt -Append
    Write-Output "==========================================================================" | Out-File -FilePath .\RubrikMS365Sizing.txt -Append
}



Write-Output "`n`nM365 Sizing information has been written to $((Get-ChildItem RubrikMS365Sizing.txt).FullName)`n`n"
if ($OutputObject) {
    return $M365Sizing
}
 