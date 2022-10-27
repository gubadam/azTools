<#
    .SYNOPSIS
    Applies tags to VMs and their RGs.

    .DESCRIPTION
    The script loops over the VM list from the CSV file 
    and applies tags specified in said CSV on Resource Group and Virtual Machine level 
    based on the column preffix values.

    .PARAMETER InputFilePath
    Specifies the name and path to the CSV-based input file containing a list of VMs and the tags to be applied, 
    which are denoted by "vmTag_*" preffix for Virtual Machine resource level tags 
    and by "rgTag_*" for Resource Group resource level tags.

    .PARAMETER OutputPath
    Specifies the path for any output files generated by this script. By default,
    MonthlyUpdates.ps1 generates a name from the date and time it runs, and
    saves the output in the local directory.

    .EXAMPLE
    PS> .\ApplyTags.ps1

    .EXAMPLE
    PS> .\ApplyTags.ps1 -InputFilePath .\someOther.csv
#>

#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.Resources

param (
    [string]
    $InputFilePath = ".\vms.csv",
    
    [string]
    $OutputPath = ".\Logs"
)

begin {
    if ($False -eq (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
    }

    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    Start-Transcript -Path "$OutputPath\$(Get-Date -Format "yyyyMMdd")-$($MyInvocation.MyCommand.Name).log" -Append -UseMinimalHeader
    
    if ($False -eq (Test-Path $InputFilePath)) {
        Throw "No input CSV file found at '$InputFilePath'"
    }
}

process {
    $inputContent = Import-Csv -Path $InputFilePath -Delimiter ";"

    $inputContent | Group-Object -Property 'VmSubscription' | ForEach-Object {
        try {
            Get-AzSubscription -SubscriptionName $_.Name | Out-Null
            Set-AzContext -Subscription $_.Name | Out-Null
            Write-Output "Processing subscription '$($_.Name)'"
        } catch {
            Write-Host "test2"
            Write-Error "Could NOT set context to subscription '$($_.Name)'. The script will NOT process it."
            Continue
        }
    
        $rgs = $_.Group | Group-Object -Property 'VmResourceGroup'
    
        $rgs | ForEach-Object -Parallel {
            $rgName = $_.Name
            $rgResource = Get-AzResourceGroup -Name $rgName
            $rgTags = $rgResource.Tags
            
            $tagsToApply = ($_.Group | Select-Object -First 1).PsObject.Properties | Where-Object {$_.Name -Like "rgTag_*"} | Select-Object Name, Value
            
            $tagsToApply | ForEach-Object {
                $tagName = ($_.Name).Replace("rgTag_","")
                if ($rgTags.Keys -notcontains $tagName) {
                    $rgTags += @{$tagName="$($_.Value)"}
                } else {
                    Write-Output "'$($rgName)' - '$($tagName)':'$($rgTags.$tagName)'"
                    $rgTags.$tagName = $_.Value
                }
                Write-Output "'$($rgName)' + '$($tagName)':'$($_.Value)'"
            }
            Set-AzResourceGroup -Name $rgName -Tags $rgTags | Out-Null
            Write-Output "'$($rgName)' : finished updating tags"
        }
    }
    Stop-Transcript
}