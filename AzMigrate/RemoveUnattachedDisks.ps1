<#
    .SYNOPSIS
    Removes orphan (unattached) Discs from specified Resource Groups.

    .DESCRIPTION
    The script loops over the Resource Groups list from the CSV file,
    removes any existing Shared Access Signatures for unattached disks in the RG
    and removes those disks.

    .PARAMETER InputFilePath
    Specifies the name and path to the CSV-based input file containing a list of RGs.

    .PARAMETER OutputPath
    Specifies the path for any output files generated by this script.

    .EXAMPLE
    PS> .\RemoveUnattachedDisks.ps1

    .EXAMPLE
    PS> .\RemoveUnattachedDisks.ps1 -InputFilePath .\someOther.csv
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

    try{ Stop-Transcript | Out-Null } catch { <# Ignore errors - ErrorAction has no impact here #> }
    Start-Transcript -Path "$OutputPath\$(Get-Date -Format "yyyyMMdd")-$($MyInvocation.MyCommand.Name).log" -Append -UseMinimalHeader
    
    if ($False -eq (Test-Path $InputFilePath)) {
        Throw "No input CSV file found at '$InputFilePath'"
    }
}

process {
    $inputContent = Import-Csv -Path $InputFilePath -Delimiter ";"

    $inputContent | Group-Object -Property 'VmSubscription' | ForEach-Object {
        try {
            Get-AzSubscription -SubscriptionName $_.Name -ErrorAction Stop | Out-Null
            Set-AzContext -Subscription $_.Name -ErrorAction Stop | Out-Null
            Write-Output "Processing subscription '$($_.Name)'"
        } catch {
            Write-Error "Could NOT set context to subscription '$($_.Name)'. The script will NOT process it."
            Continue
        }
    
        $rgs = $_.Group | Group-Object -Property 'vmResourceGroup'
        $rgs | ForEach-Object -Parallel {
            $rgName = $_.Name
        
            <#
            $diskAccess = Grant-AzDiskAccess -ResourceGroupName rg-test-1 -DiskName testDisk1 -Access Read -DurationInSecond (60*60*24)
            #>

            $unattachedDisks = Get-AzDisk -ResourceGroupName $rgName | ? {$_.ManagedBy -eq $Null}
            $unattachedDisks | ? {$_.DiskState -eq "ActiveSAS"} | Revoke-AzDiskAccess | Out-Null
            $unattachedDisks | ForEach-Object -Parallel {
                Remove-AzDisk -ResourceGroupName $_.ResourceGroupName -DiskName $_.Name -Force | Out-Null
                Write-Output "'$($_.Name)' : Deleted"
            }
        }
    }
    
}

end {
    Stop-Transcript
}