Import-Module "$PSScriptRoot\Functions.psm1"  -DisableNameChecking

if (!$PackageData){
	Load-PSM "Convergence-Package"
}
Load-Module Microsoft.PowerApps.Administration.PowerShell
<#
Install the PowerApp CLI toolset.
#>
function InstallPAC(){
	# if the package.yml specifies what PACVersion to use, use it.
	if ($PackageData.PACVersion){
		Write-Host "Build-NuGet, Package: Microsoft.PowerApps.CLI with version: $($PackageData.PACVersion)"
		$pacInstallPath = Build-NuGet -package Microsoft.PowerApps.CLI -version $PackageData.PACVersion
	} else {
		Write-Host "Build-NuGet, Package: Microsoft.PowerApps.CLI Latest"
		$pacInstallPath = Build-NuGet -package Microsoft.PowerApps.CLI
	}

    Write-Host $pacInstallPath

    # find the executable and add it to the environment path
    $pacPath = Join-Path -Path $pacInstallPath  "\tools"

	Write-Host "PacPath: '$pacPath'"
    # if the path does not contain the pacPath, then add it.
    if (!($env:PATH.Contains($pacPath))){
	    $env:PATH += ";$pacPath"
	    #Add pac to the path into DevOps pipeline
	    Write-Host "##vso[task.setvariable variable=PATH;]${env:PATH}";
    }

	Write-Host "PAC Details"
	$output = pac
	$output | ForEach-Object {Write-Host $_}
}

<#
Set the PAC Connection and connect to the dataverse
#>
function Set-PacConnection(){
	param(
		[string]$targetEnvironment, # Cloud Environment name (*.crm3.dynamics.com)
		[string]$appId, # optional app id to connect to dataverse
		[string]$clientSecret, #  client secret for the app id
		[string]$tenant
	)
	$pacVersion = "1.23.4"
    if ($targetEnvironment -eq ""){
        Write-Warning "No Target Environment Specified"
    }
	# Check to make sure the power platform cli is installed and available.
	if ((Get-Command "pac" -ErrorAction SilentlyContinue) -eq $null) 
	{ 
		InstallPAC
	}


	# Check to make sure the power platform cli is installed and available.
	if ((Get-Command "pac" -ErrorAction SilentlyContinue) -eq $null) 
	{ 
		Write-Host "Unable to find Power Platform CLI"
		Write-Host "Please install it from: https://docs.microsoft.com/en-us/power-platform/developer/cli/introduction"
	}
	
	if (!$targetEnvironment.EndsWith("-conv")){
		$targetEnvironment = "$targetEnvironment-conv"
	}

	$url = "https://$targetEnvironment.crm3.dynamics.com/"

	# Check if the connection can be selected.
	# if we get back an error on selecting the connection, then it doesn't exist and we must create it. 
	if (pac auth select --name "$targetEnvironment" | Select-String -Pattern "^Error:"){
		Write-Host "Creating authentication profile for $targetEnvironment Url: $url"
		# if not, create it.
		if ($appId){
			Write-Host "Connecting with App Id: $appId"
			pac auth create --name $targetEnvironment --url $url --environment $url --applicationId $appId  --clientSecret $clientSecret  --tenant $tenant
		} else {
			Write-Host "Connecting Interactive"
			pac auth create --name $targetEnvironment --url $url  --environment $url
		}
	} else {
		Write-Host "$targetEnvironment Found"
	}
	Write-Host "pac switching auth to $targetEnvironment"
	if (pac auth select --name "$targetEnvironment" | Select-String -Pattern "^Error:"){
		throw "Unable to switch to '$targetEnvironment'"
	}
}


<#
Set the Admin PAC connection
#>
function Set-PacConnectionAdmin(){
	param(
		[string]$targetEnvironment, # Cloud Environment name (*.crm3.dynamics.com)
		[string]$appId , # optional app id to connect to dataverse
		[string]$clientSecret, #  client secret for the app id
		[string]$tenant 
	)
    if ($targetEnvironment -eq ""){
        Write-Warning "No Target Environment Specified"
    }

	# Check to make sure the power platform cli is installed and available.
	if ((Get-Command "pac" -ErrorAction SilentlyContinue) -eq $null) 
	{ 
		InstallPAC
	}

	# Check to make sure the power platform cli is installed and available.
	if ((Get-Command "pac" -ErrorAction SilentlyContinue) -eq $null) 
	{ 
		Write-Host "Unable to find Power Platform CLI"
		Write-Host "Please install it from: https://docs.microsoft.com/en-us/power-platform/developer/cli/introduction"
	}

	if (!$targetEnvironment.EndsWith("-conv")){
		$targetEnvironment = "$targetEnvironment-conv"
	}

	$url = "https://$targetEnvironment.crm3.dynamics.com/"

	$adminEnvName = "$targetEnvironment-admin"
	# Check if the connection can be selected.
	# if we get back an error on selecting the connection, then it doesn't exist and we must create it. 
	if (pac auth select --name "$adminEnvName" | Select-String -Pattern "^Error:"){
		Write-Host "Creating Admin authentication profile for $adminEnvName Url: $url"
		# if not, create it.
		if ($appId){
			Write-Host "Connecting with App Id: $appId"
			pac auth create --name $adminEnvName --url $url --environment $url --applicationId $appId  --clientSecret $clientSecret  --tenant $tenant --kind admin
			Write-Host "Connecting with Microsoft.PowerApps.Administration.PowerShell"
			Add-PowerAppsAccount -ApplicationId $appId -ClientSecret $clientSecret -TenantID $tenant
		} else {
			Write-Host "Connecting Interactive"
			pac auth create --name $adminEnvName --url $url  --environment $url  --kind admin
			Write-Host "Connecting with Microsoft.PowerApps.Administration.PowerShell"
			Add-PowerAppsAccount 
		}
	} else {
		Write-Host "$targetEnvironment-admin Found"
	}
	Write-Host "pac switching auth to $adminEnvName"
	if (pac auth select --name "$adminEnvName"  | Select-String -Pattern "^Error:"){
		throw "Unable to switch to '$adminEnvName'"
	}
}


<#
Wuery and get an admin status
#>
function Get-AdminStatus(){
	$statusOutput = pac admin status | Out-String
	$statusOutput = $statusOutput.Trim()
	if ($statusOutput.StartsWith("No async operation")){
		return $null
	}
	$statusOutput = $statusOutput.Replace("   ", ",")

	while ($statusOutput.Contains(",,")){
		$statusOutput = $statusOutput.Replace(", ", ",")
		$statusOutput = $statusOutput.Replace(",,", ",")
	}
	
	$status = $statusOutput | ConvertFrom-Csv
	return $status
}


<#
Create a Power Platform Environment
#>
function Create-PPEnvironment(){
	param(
		[string] $targetEnvironment , # source environment
		[string] $SecurityGroupId,
		[string] $locationRegion,
		[switch] $deleteExisting
	)

	# append "-conv" if it is not specified
	if (!$targetEnvironment.EndsWith("-conv")){
		$targetEnvironment = "$targetEnvironment-conv"
	}

	# if the location region is not specified, default to "Canada Central"
	if (!$locationRegion){
		$locationRegion = "canadacentral"
	}
	
	Write-Host ""
	Write-Host ""
	Write-Host "**************************************************************"
	Write-Host "Checking if target $targetEnvironment exists"
	Write-Host "**************************************************************"

	$targetUrl = "https://$targetEnvironment.crm3.dynamics.com/"
	# get all environments with the display name of the target environment.
	# Question will Prod have the same display name as the targetEnvironment, 
	#$targetEnv = Get-AdminPowerAppEnvironment | Where {$_.Internal.properties.linkedEnvironmentMetadata.instanceUrl -eq $targetEnvironment }
	$targetEnv = Get-AdminPowerAppEnvironment | Where {$_.DisplayName -eq $targetEnvironment }
	
	
	if ($targetEnv){
		Write-Host "Environment already exists"
		if ($deleteExisting){		
			Write-Host "   Deleting environment"
			Remove-AdminPowerAppEnvironment -EnvironmentName $targetEnv.EnvironmentName | Out-Null
			Write-Host "   Waiting for Delete to finish" -NoNewline
			while ($targetEnv){
				$targetEnv = Get-AdminPowerAppEnvironment | Where {$_.DisplayName -eq  $targetEnvironment }
				Write-Host ".." -NoNewline
				Start-Sleep 3
			}
			Write-Host ""
			$maxSleepSeconds = 30
			Write-Host "   Waiting $maxSleepSeconds seconds before creating to ensure we create in the correct region" -NoNewline
			for ($count = 0; $count -lt $maxSleepSeconds; $count++){
				Write-Host "." -NoNewline
				Start-Sleep 1
			}
			Write-Host ""
		}
	}

	# if it now exists create it.
	if (!$targetEnv){
		$description = "The Convergence Power Apps Environment for: $targetEnvironment"
		Write-Host ""
		Write-Host "************************************************"
		Write-Host "Environment does not exist, creating"
		Write-Host "************************************************"
		Write-Host "   Display Name: $targetEnvironment"
		Write-Host "   Domain Name: $targetEnvironment"
		Write-Host "   Location: Canada"
		Write-Host "   Region: $locationRegion"
		Write-Host "   Currency: CAD"
		Write-Host "   Type: Sandbox"
		Write-Host "   Description: $description"
		Write-Host "New-AdminPowerAppEnvironment -DisplayName $targetEnvironment -DomainName $targetEnvironment -Description $description -RegionName $locationRegion -LocationName canada -SecurityGroupId $SecurityGroupId -EnvironmentSku Sandbox -CurrencyName CAD  -ProvisionDatabase -WaitUntilFinished $true"
		if ($SecurityGroupId){
			Write-Host "   With Security Group Id: $SecurityGroupId"
			$targetEnv = New-AdminPowerAppEnvironment -DisplayName $targetEnvironment -DomainName $targetEnvironment -Description $description -RegionName $locationRegion -LocationName canada -SecurityGroupId $SecurityGroupId -EnvironmentSku Sandbox -CurrencyName CAD  -ProvisionDatabase -WaitUntilFinished $true
		} else {
			Write-Host "   With No Security Group"
			$targetEnv = New-AdminPowerAppEnvironment -DisplayName $targetEnvironment -DomainName $targetEnvironment -Description $description -RegionName $locationRegion  -LocationName canada -EnvironmentSku Sandbox -CurrencyName CAD -ProvisionDatabase -WaitUntilFinished $true
		}
	}
}


# Uses the Powershell Power Apps Admin Module
#https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/copy-powerappenvironment?view=pa-ps-latest
function Copy-PAppEnvironment(){
	param(
		[string]$sourceEnvironment , # source environment
		[string]$targetEnvironment,  # target environment
		[string]$SecurityGroupId,
		[boolean]$skipAuditData = $true
	)
	Write-Host ""
	Write-Host "=================================================================="
	Write-Host "Copying $sourceEnvironment-conv to $targetEnvironment-conv"
	Write-Host "=================================================================="
	if (!$sourceEnvironment.EndsWith("-conv")){
		$sourceEnvironment = "$sourceEnvironment-conv"
	}
	if (!$targetEnvironment.EndsWith("-conv")){
		$targetEnvironment = "$targetEnvironment-conv"
	}

	$sourceEnvironmentData = Get-AdminPowerAppEnvironment | Where {$_.DisplayName -eq $sourceEnvironment }
	$targetEnvironmentData = Get-AdminPowerAppEnvironment | Where {$_.DisplayName -eq $targetEnvironment }

	if (!$targetEnvironmentData){
		throw "target $targetEnvironment environment does not exist, please create it."
	}

	$copyToRequest = @{
		"SourceEnvironmentId" = $sourceEnvironmentData.EnvironmentName
		"TargetEnvironmentName"= $targetEnvironment
		"CopyType" = "FullCopy" #"MinimalCopy"
		"SkipAuditData" = $skipAuditData
	}

	if ($SecurityGroupId){
		Write-Host "Security Group: $SecurityGroupId"
		$copyToRequest.TargetSecurityGroupId = $SecurityGroupId
	}

	$copyToRequest = [pscustomobject]$copyToRequest
	Write-Host "Using Copy-PowerAppEnvironment to copy $sourceEnvironment to $targetEnvironment"
	$copyToRequest | Format-List

	$response = Copy-PowerAppEnvironment -EnvironmentName $targetEnvironmentData.EnvironmentName -CopyToRequestDefinition $copyToRequest 

	# TODO new version of the module returns a System.Net.WebHeaderCollection need to convert that to a has
	# convert the headers dictionary to a hashtable
	$headers = [hashtable]$response.Headers
	#$headers | Format-List
	$operationUrl = $headers."operation-location"

	if (!$operationUrl -or $operationUrl -eq ""){
		throw "Unable to get a status operational url to query."
	}
	Write-Host "Operation Status URL: $operationUrl"

	Start-Sleep 5

	$operationResponse = Get-AdminPowerAppOperationStatus -OperationStatusUrl $operationUrl
	$response = $operationResponse.Internal.Content | ConvertFrom-Json

	$copyStart = (Get-Date)
	$timePassed = (Get-Date).Subtract($copyStart)


	while ($response -and $response.state.id -eq "Running"){
		Start-Sleep 20
		$operationResponse = Get-AdminPowerAppOperationStatus -OperationStatusUrl $operationUrl
		$response = $operationResponse.Internal | ConvertFrom-Json
		$timePassed = (Get-Date).Subtract($copyStart)

		Write-Host "************ Status ************"
		$validateStage = $response.stages | Where {$_.id -eq "Validate"}
		$prepare = $response.stages | Where {$_.id -eq "Prepare"}
		$run = $response.stages | Where {$_.id -eq "Run"}
		$finalize = $response.stages | Where {$_.id -eq "Finalize"}

		$dateStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		Write-Host "DateStamp  $dateStamp"
		Write-Host "Run Time   $($timePassed.Hours) Hours, $($timePassed.Minutes) minutes, $($timePassed.Seconds) seconds"
		Write-Host "Validate:  $($validateStage.state.id)"
		Write-Host "Prepare:   $($prepare.state.id)"
		Write-Host "Copy Run:  $($run.state.id)"
		Write-Host "Finalize:  $($finalize.state.id)"
		Write-Host "********************************"		
	}

	Write-Host "Enabling the environment (aka disabling admin mode)"
	$response = Set-AdminPowerAppEnvironmentRuntimeState -EnvironmentName $targetEnvironmentData.EnvironmentName -RuntimeState Enabled

	#$jsonResponse = $response.Internal | ConvertFrom-Json 
	#$jsonResponse | Format-List
}


<#
Initialzies the pac cli connection details
#>
function InitializePACConnections(){

    Write-Host ""
    Write-Host ""
    Write-Host "************************************************"
    Write-Host "Initializing PAC Connections"
    Write-Host "************************************************"
    # Check to make sure the power platform cli is installed and available.
	if ((Get-Command "pac" -ErrorAction SilentlyContinue) -eq $null) 
	{ 
		InstallPAC
	}
    if ($global:PACConnectionDetails.resetAuth){
		# disabled delete and going back to clear until time permits to test and debug
        #Write-Host "Deleting PAC Connections: $targetEnvironment and $targetEnvironment-admin"
        #pac auth delete --name "$targetEnvironment-admin" | Out-Null
		#pac auth delete --name $targetEnvironment | Out-Null
		Write-Host "Clearing PAC Connections"
		pac auth clear
    }
  
    if ($global:PACConnectionDetails.requireAdmin){
        # Set the Admin Connection First
        Set-PacConnectionAdmin  -targetEnvironment $global:PACConnectionDetails.targetEnvironment -appId $global:PACConnectionDetails.appId -clientSecret $global:PACConnectionDetails.clientSecret -tenant $global:PACConnectionDetails.tenant
    }

    # Set the Pac default Connection
    Set-PacConnection  -targetEnvironment $global:PACConnectionDetails.targetEnvironment -appId $global:PACConnectionDetails.appId -clientSecret $global:PACConnectionDetails.clientSecret -tenant $global:PACConnectionDetails.tenant

    Write-Host ""
    Write-Host ""
    pac auth list
    Write-Host ""
    Write-Host ""
}


$global:PACConnectionDetails = @{}
function InitializeConvergenceBuild(){
    param(
        [string] $targetEnvironment,
        [string] $appId, # optional app id to connect to dataverse
	    [string] $clientSecret, #  client secret for the app id
	    [string] $tenant,
        [switch] $logConfig,
        [switch] $requireAdmin,
        [switch] $resetAuth
    )
    #default tenant if it is not set
    if (!$tenant){
       $tenant  = "fbef0798-20e3-4be7-bdc8-372032610f65"
    }
    Load-PackageData -targetEnvironment $targetEnvironment -logConfig:$logConfig

    # Set Connection Details
    $global:PACConnectionDetails.targetEnvironment = $targetEnvironment
    $global:PACConnectionDetails.appId = $appId
    $global:PACConnectionDetails.clientSecret = $clientSecret
    $global:PACConnectionDetails.tenant = $tenant
    $global:PACConnectionDetails.logConfig = $logConfig
    $global:PACConnectionDetails.tenant = $tenant
    $global:PACConnectionDetails.resetAuth = $resetAuth
    $global:PACConnectionDetails.requireAdmin = $requireAdmin

    InitializePACConnections 
    
}


<#
Set and configure the Deployment Solution-Settings.json file
#>
function Set-SolutionSettingsJson(){
	param(
		[string] $SolutionSettingsFile, 
		# Connection Identifier to update the solution settings file with.
		[string] $dataverseConnectorId,
		[string] $sharePointConnectorId
	)

	
	if (!$dataverseConnectorId){
		throw "No Dataverse Connector Id was specified"
	}

	# Load the Soltuion Settings file
	$jsonFileContents = Get-Content -Path $SolutionSettingsFile 

	# Convert from a json string to a PS Object
	$solutionSettings = $jsonFileContents | ConvertFrom-Json

	
	# process the file updating the connection id to the connection identifer script parameter
	Write-Host "========================================================="
	Write-Host " Processing Connection References"
	Write-Host "========================================================="
	$solutionSettings.ConnectionReferences | ForEach-Object {
		$reference = $_;
		$logicalName = $reference.LogicalName;

		Write-Host ""
		Write-Host "-------------------------------------------"
		Write-Host "Processing $logicalName"

		# if the connector type is common data servece (dataverse), use the datverse connector id
		if ($reference.ConnectorId -eq "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"){
			Write-Host "    Connection Reference Type: Dataverse"
			Write-Host "    Setting connector Id: $dataverseConnectorId"
			$reference.ConnectionId = $dataverseConnectorId
		}
		# if the connector id is sharepoint
		# use the sharepoit connector id.
		elseif ($reference.ConnectorId -eq "/providers/Microsoft.PowerApps/apis/shared_sharepointonline"){
			Write-Host "    Connection Reference Type: SharePoint"
			Write-Host "    Setting connector Id: $dataverseConnectorId"
			$reference.ConnectionId = $sharePointConnectorId
		} 
	
		$overrideValue = [Environment]::GetEnvironmentVariable($logicalName);
		if ($overrideValue){
			Write-Host "    Connection Reference Type: $($reference.ConnectorId)"
			Write-Host "    Using Environment Variable $logicalName to set the value"
			Write-Host "    Setting connector Id: $overrideValue"
			$reference.ConnectionId = $overrideValue
		}

		if (!$reference.ConnectionId){
			Write-Host "    Connection Reference Type: $($reference.ConnectorId) not supported"
			Write-Host "      OR no environment variable '$logicalName' is defined to use."
			Write-Host "    Leaving blank."
			Write-Host "      To set a connector please define a pipeline variable '$logicalName', with the connector id as the value."
		}

		Write-Host "-------------------------------------------"	
	}

	# Iterate over the environment variables, setting
	# them to the system env variable matching by name
	$solutionSettings.EnvironmentVariables | ForEach-Object {
		$variable = $_;

		$schemaName = $variable.SchemaName;

		#update the value to the environment variable value
		$variable.Value = [Environment]::GetEnvironmentVariable($schemaName);

		if ($variable.Value -eq $null){
			throw "Missing Environment Variable: '$schemaName'.  Please update the pipeline and add the missing variable.";
		}
	}

	# define the output file name
	$outputfilename = $SolutionSettingsFile

	# output the update connecitons to the output file name.
	$solutionSettings | ConvertTo-Json  -Depth 100 | Out-File -Encoding UTF8 -FilePath $outputfilename

	$updatedFileLines =  Get-Content -Path $outputfilename

	Write-Host ""
	Write-Host ""
	Write-Host "========================================================="
	Write-Host " Solution-Setting.json"
	Write-Host "========================================================="
	$updatedFileLines | ForEach-Object {
		Write-Host $_
	} 

}


<#
Import the Solution to the target environment
#>
function ImportSolution(){
	param(
		[string] $solutionZipFile, 
		[string] $targetEnvironment,
		[string] $solutionSettingsFile,
		[string] $solutionName
	)

	# Update the Solution-Settings.json with the connector id.
	# update the import to use the soltuion-settings.json file.

	$solutionSettingsFile = "$($PackageData.BuildPackagePath)\Solution-Settings.json"
    Write-Host $solutionSettingsFile

	Write-Host "Create the Solution Settings File"
	pac solution create-settings --solution-zip $solutionZipFile --settings-file $solutionSettingsFile

	Set-SolutionSettingsJson -SolutionSettingsFile $solutionSettingsFile -dataverseConnectorId $env:PowerAppsConnectorId
	
	$stopwatch =  [system.diagnostics.stopwatch]::StartNew()
	$LastExitCode = 0
	Write-Host pac solution import --path $solutionZipFile --activate-plugins --force-overwrite --settings-file $solutionSettingsFile --async 
	
	pac solution import --path $solutionZipFile --activate-plugins --force-overwrite --settings-file $solutionSettingsFile --async > output.log 
	$stopwatch.Stop()
	if (($LastExitCode -ne 0 ) -or (Get-Content .\output.log | Select-String -Pattern "^Error:")){
		Write-Host "Last Error Code: $LastExitCode"
		Write-Host "***********************************************"
		Write-Host " Error importing, Log output: "
		Write-Host "***********************************************"
		cat output.log
		throw "Failed to import solution $solutionZipFile"
	} 
	Write-Host "Took $($stopwatch.Elapsed.Minutes) minutes,  $($stopwatch.Elapsed.Seconds) seconds to import $filePath"
	PublishSolutions
	

	# Enable all Cloud Flows, Workflows, Actions, Dialogs in the given solution that are in draft status

	Write-Host "Activating solution Cloud Flows, Workflows, Actions, Dialogs, Actions in draft status..."    

	$fetch="<fetch version='1.0' output-format='xml-platform' mapping='logical' distinct='false' >
				<entity name='solutioncomponent' >
					<attribute name='solutioncomponentid' />
					<link-entity name='solution' from='solutionid' to='solutionid' >
						<attribute name='solutionid' alias='solutionid' />
						<attribute name='uniquename' alias='uniquename'/>
						<attribute name='friendlyname' alias='friendlyname' />
						<filter>
							<condition attribute='uniquename' operator='eq' value='$solutionName' />
						</filter>
					</link-entity>
					<link-entity name='workflow' from='workflowid' to='objectid' >
						<attribute name='workflowid' alias='workflowid' />						
						<attribute name='name' alias='flowname'  />
						<filter type='and' >
							<condition attribute='type' operator='eq' value='1' />
							<filter type='and' >
								<condition attribute='rendererobjecttypecode' operator='null' />
								<condition attribute='category' operator='in'>
									<value>0</value>
									<value>1</value>
									<value>3</value>
									<value>5</value>
								</condition>
							</filter>
							<condition attribute='statecode' operator='eq' value='0' />
						</filter>
					</link-entity>
				</entity>
			</fetch>
			"
	
	 
	
    # get the results, and if non are found, skip step
    $results = get-crmrecordsbyfetch  -conn $Conn -Fetch $fetch 
    if ($results.Count -eq 0){
		Write-Host "No Cloud Flows, Workflows, Dialogs or Actions to activate."                  
    }
	else{
		# Activate all draft state cloud flows, workflows, actions and dialogs found in solution			
		$count = 0
		$activatedCount = 0;
		$totalCount = $results.CrmRecords.Count
		Write-Host "Activating $totalCount Processes..." 
		foreach($record in $results.CrmRecords) {
			$count++
			$name = $record."flowname".Value
			$flowid = $record.workflowid
			Write-Debug "workflowid: $flowid"
			Write-Host "($count/$totalCount) Activating Process '$name'" 
			Try
			{
				Set-CrmRecordState -Conn $Conn -Id $flowid -EntityLogicalName "workflow" -State 1 -Status 2
			}
			Catch
			{
				Write-Host "An error occured activating the Process '$name' id: '$flowid', skipping..." 
				$PSItem.Exception.Message
			}
		}
	}

	# North 52 wait for publish step 
	Write-Debug "Waiting for North 52 Publish to complete..." 
	WaitForNorth52 -timeout 60 -queryWait 30000
}

<#
Runs a Publish All
#>
function PublishSolutions(){
    InitializePACConnections
    Write-Host ""
    Write-Host "***********************************************"
    Write-Host "Publishing Changes"
    Write-Host "***********************************************"
    pac solution publish
    # if published failed
    if ($LastExitCode -ne 0 ){
        Write-Host "Publish FAILED: "
        Write-Host "   failed to publish all, after importing solutions.  Ignroing failure"
           
        $LastExitCode = 0
        $Error.Clear() 
    }else{
        Write-Host "Publish successful"
    }
    Write-Host "-----------------------------------------------------------------"

}



Export-ModuleMember -Function * -Alias *
