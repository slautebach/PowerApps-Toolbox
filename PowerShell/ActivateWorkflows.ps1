<#
  .SYNOPSIS
  Looks at the cloud flow and work flows, and activate any flows (logs errors).


  .DESCRIPTION


  .PARAMETER all 

  targetEnvironment - the target envrinment to execute on.  https://<targetEnvironment>.crm3.dynamics.com/
  solution - the solution unique name to find the flows to activate
  appId - optional to supply appid/clientsecret credential. If blank, it will prompt for connection
  clientSecret - the app id client secret used to connect.
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $targetEnvironment = "",
    [string] $solution = "",
    [string] $appId = $env:AppId,
    [string] $clientSecret = $env:ClientSecret,
    [string] $tenantId = $env:TenantId
    [string] $flowOwingUserName = ""
) 

# for Prod flowOwingUserName needs to be set to: svc_prod_pad365con@cfpsa.com

# Import common functions
Import-Module "$PSScriptRoot\Dataverse-API.psm1" -Force  -DisableNameChecking

# Log Script Invcation Details
LogInvocationDetails $MyInvocation


ConnectDataverseApi  -targetEnvironment $targetEnvironment -appId $appId -clientSecret $clientSecret

$flowOwingUserRecord = $null
if ($flowOwingUserName){
    # Get the user record for the flowOwingUserName so we know the systemuserid of the owner to set.
    $fetch = "<fetch version='1.0' output-format='xml-platform' mapping='logical' distinct='true'>
    <entity name='systemuser'>
      <attribute name='domainname' />
      <attribute name='firstname' />
      <attribute name='fullname' />
      <attribute name='lastname' />
      <attribute name='systemuserid' />
      <filter>
        <condition attribute='domainname' operator='eq' value='$flowOwingUserName' />
      </filter>
    </entity>
    </fetch>"

    #validate and format the fetchxml
    $fetchXml = [xml]$fetch
    $fetch = $fetchXml.OuterXml
    Write-Host "Fetch:"
    Write-Host "$fetch"

    Write-Host "--------------------------------------------------"
    Write-Host "Retreiving flow owing user"
    Write-Host ""
    try {
        # get the results, and if non are found return null
        $dataFilterFetchResults = get-crmrecordsbyfetch  -conn $Conn -Fetch $fetch
        $flowOwingUserRecord = $dataFilterFetchResults.CrmRecords[0]
    }
    catch {
        Write-Warning "Unable to retrieve records, for entity: workflow"
        $_ | Format-List
        exit;
    }
}

Write-Host ""
Write-Host "=================================================================="
Write-Host "Find Workflow under solution: $solution "
Write-Host "=================================================================="
$fetch = "<fetch version='1.0' output-format='xml-platform' mapping='logical' distinct='true'>
<entity name='workflow'>
  <attribute name='name' />
  <attribute name='category' />
  <attribute name='statecode' />
  <attribute name='statuscode' />
  <attribute name='workflowid' />
  <attribute name='ownerid' />
  <order attribute='modifiedon' descending='false' />
  <link-entity name='solutioncomponent' from='objectid' to='workflowid' link-type='inner' alias='sc'>
    <link-entity name='solution' from='solutionid' to='solutionid' link-type='inner' alias='solution'>
      <attribute name='uniquename' />
      <filter>
        <condition attribute='uniquename' operator='eq' value='$solution' />
      </filter>
    </link-entity>
  </link-entity>
</entity>
</fetch>"

#validate and format the fetchxml
$fetchXml = [xml]$fetch
$fetch = $fetchXml.OuterXml
Write-Host "Fetch:"
Write-Host "$fetch"

Write-Host "--------------------------------------------------"
Write-Host "Retreiving workflows"
Write-Host ""
try {
    # get the results, and if non are found return null
    $dataFilterFetchResults = get-crmrecordsbyfetch  -conn $Conn -Fetch $fetch
}
catch {
    Write-Warning "Unable to retrieve records, for entity: workflow"
    $_ | Format-List
    exit;
}

enum WorkflowCategory {
    Workflow = 0
    Dialog = 1
    BusinessRule = 2
    Action = 3
    BusinessProcessFlow = 4
    ModernFlow = 5 # cloud flow
    DesktopFlow = 6
}

[System.Collections.ArrayList]$workflowsActivate = @()
[System.Collections.ArrayList]$workflowsDeactiate = @()
[System.Collections.ArrayList]$workflowsOwnerShip = @()
# stautscode 2 = Activated, statecode 1 = Activated
foreach ($record in $dataFilterFetchResults.CrmRecords) {
    $count++
    $name = $record.name
    $category = $record.category
    $categoryInt = $record.category_Property.Value.Value
    $ownerGuid = $record.ownerid_Property.Value.Id
    $statuscodeValue = $record.statuscode_Property.Value.Value
    $statecodeValue = $record.statecode_Property.Value.Value

    # if a depreacated work flow is active, deactivate it.
    if ($name.ToLower().Contains("deprecated")) {
        Write-Host "Found Workflow to Deactivate: ($category) '$name'"    
        $workflowsDeactiate += $record;
    }
    # if the workflow is not deprecated and not active, activate it.
    elseif ($statecodeValue -ne 1 -and $statuscodeValue -ne 2) {
        Write-Host "Found Workflow to Activate: ($category) '$name', State: $statecodeValue, status: $statuscodeValue"    
        $workflowsActivate += $record;
    }

    # check about changing ownership of the cloud flows
    if ($categoryInt -eq [WorkflowCategory]::ModernFlow -and $flowOwingUserRecord -and ($ownerGuid -ne $flowOwingUserRecord.systemuserid)) {
        Write-Host "Found Cloudflow to Change Ownership:'$name'"
        $workflowsOwnerShip += $record;
    }
}




Write-Host "--------------------------------------------------"
Write-Host "******** Update Cloud Flow Ownership ************"
Write-Host "--------------------------------------------------"

$totalCount = $workflowsOwnerShip.Count
$count = 0
Write-Host "Total Cloudflows to change ownership: $totalCount"
foreach ($record in $workflowsOwnerShip.ToArray()) {
    $count++
    $name = $record.name
    $id = $record.workflowid
    $category = $record.category
    $categoryInt = $record.category_Property.Value.Value
    Write-Host "($count/$totalCount) Setting Cloud flow '$name' ($id) Owner to: $($flowOwingUserRecord.systemuserid)"    
    try {  
        Set-CrmRecordOwner $record -PrincipalId $flowOwingUserRecord.systemuserid
    }
    catch {
        Write-Warning "Unable to assign ownership workflow: $name"
        $_ | Format-List
        exit
        
    }
}

$retryAttempts = 3
Write-Host ""
Write-Host ""
Write-Host "--------------------------------------------------"
Write-Host "******** Activating Workflows ************"
Write-Host "--------------------------------------------------"
$activateFailures = @{}
for ($i = 0; $i -lt $retryAttempts; $i++) {

    $totalCount = $workflowsActivate.Count
    if ($totalCount -eq 0) {
        Write-Host "No workflows to activate."
        # nothting to deactivate skip.
        $i = $retryAttempts
        continue
    }

    Write-Host "--------------------------------------------------"
    Write-Host "Activate Workflows attempt $($i + 1) of $retryAttempts"
    Write-Host ""
    

    Write-Host "Total workflows to activate: $totalCount"
    $count = 0
    $activatedCount = 0;
    $activateFailures.Clear()
    foreach ($record in $workflowsActivate.ToArray()) {
        $count++
        $name = $record.name
        $id = $record.workflowid
        $category = $record.category
        Write-Host "($count/$totalCount) Activating workflow ($category) '$name' ($id)"    
        try {
            Set-CrmRecordState  -conn $Conn -CrmRecord $record  -StateCode 1 -StatusCode 2
            $activatedCount++
            $workflowsActivate.Remove($record) ;
        }
        catch {
            $activateFailures[$name] = $_
            Write-Warning "Unable to activate workflow: $name"
        }
    }
    Write-Host ""
    Write-Host ""
    Write-Host "Activated a total of $activatedCount workflows within attempt $($i + 1) of $retryAttempts."  
}


Write-Host "--------------------------------------------------"
Write-Host "****** Deactiving Deprecated Workflows ***********"
Write-Host "--------------------------------------------------"


$deactivateFailures = @{}
for ($i = 0; $i -lt $retryAttempts; $i++) {
    $totalCount = $workflowsDeactiate.Count
    if ($totalCount -eq 0) {
        Write-Host "No workflows to deactivate."
        $i = $retryAttempts
        continue
    }

    Write-Host "--------------------------------------------------"
    Write-Host "Deactivate Workflows attempt $($i + 1) of $retryAttempts"
    Write-Host ""
    
   
    Write-Host "Total workflows to deactivate: $totalCount"
    $count = 0
    $activatedCount = 0;
    $deactivateFailures.Clear()
    foreach ($record in $workflowsDeactiate.ToArray()) {
        $count++
        $name = $record.name
        $category = $record.category
        Write-Host "($count/$totalCount) Deactivating Workflow ($category) '$name'"    
        try {
            Set-CrmRecordState  -conn $Conn -CrmRecord $record  -StateCode 0 -StatusCode 1
            $activatedCount++
            $workflowsDeactiate.Remove($record) ;
        }
        catch {
            $deactivateFailures[$name] = $_
            Write-Warning "Unable to activate workflow: $name"
        }
    }
    Write-Host ""
    Write-Host ""
    Write-Host "Deactivated a total of $activatedCount workflows within attempt $($i + 1) of $retryAttempts."  
}
Write-Host "--------------------------------------------------"


if ($activateFailures.Count -gt 0 -or $deactivateFailures.Count -gt 0 ) {
    Write-Host ""
    Write-Host ""
    Write-Host "*******************************************************"
    Write-Host "********             Failure Detials       ************"
    Write-Host "*******************************************************"

    foreach ($k in $activateFailures.Keys) {
        Write-Host "----------------------------------------------------------------------------------------------------"
        Write-Host "Failed to activate Workflow: $k"
        Write-Host "----------------------------------------------------------------------------------------------------"
        Write-Host $activateFailures[$k]
        Write-Host ""
        Write-Host ""
    }
}


Write-Host ""
Write-Host ""
Write-Host "*******************************************************"
Write-Host "********     Duplicate Detection Rules     ************"
Write-Host "*******************************************************"
$duplicateDetection = "<fetch version='1.0' output-format='xml-platform' mapping='logical' distinct='true'>
  <entity name='duplicaterule'>
    <attribute name='duplicateruleid' />
    <attribute name='name' />
    <attribute name='statecode' />
    <attribute name='statuscode' />
    <attribute name='uniquename' />
    <link-entity name='solutioncomponent' from='objectid' to='duplicateruleid' link-type='inner' alias='sc'>
      <link-entity name='solution' from='solutionid' to='solutionid' link-type='inner' alias='solution'>
        <attribute name='uniquename' />
        <filter>
          <condition attribute='uniquename' operator='eq' value='$solution' />
        </filter>
      </link-entity>
    </link-entity>
  </entity>
</fetch>"

# Activate the SISIP solution duplicate detection rules
Set-DuplicateDectionRules -fetch $duplicateDetection -enable $true
