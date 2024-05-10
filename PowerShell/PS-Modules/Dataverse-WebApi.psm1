# Taken and based off of: https://github.com/microsoft/PowerApps-Samples/tree/master/dataverse/webapi/PS

# Set to $true only while debugging with Fiddler
$debug = $false
# Set this value to the Fiddler proxy URL configured on your computer
$proxyUrl = 'http://127.0.0.1:8888'

Import-Module "$PSScriptRoot\Functions.psm1" -DisableNameChecking

# Install/Load the dependency modules
Load-Module Microsoft.PowerShell.Utility
Load-Module Az.Accounts


<#
.SYNOPSIS
Connects to Dataverse Web API using Azure authentication.

.DESCRIPTION
The Connect function uses the Get-AzAccessToken cmdlet to obtain an access token for the specified resource URI. 
It then sets the global variables baseHeaders and baseURI to be used for subsequent requests to the resource.

.PARAMETER uri
The resource URI to connect to. This parameter is mandatory.

.EXAMPLE
Connect -uri 'https://yourorg.crm.dynamics.com'
This example connects to Dataverse environment and sets the baseHeaders and baseURI variables.
#>

function Connect {
    param (
        [Parameter(Mandatory)] 
        [String] $uri,
        [String] $appId = $env:AppId,
        [String] $clientSecret = $env:ClientSecret,
        [String] $tenantId = $env:TenantId
    )

    if ($appId -ne "" -and $clientSecret -ne "" -and $tenantId -ne "") {
        $password = ConvertTo-SecureString $clientSecret -AsPlainText -Force
        $cred = New-Object -TypeName PSCredential -ArgumentList $appId, $password
        Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $tenantId | Out-Null
    }
    ## Login if not already logged in
    if ($null -eq (Get-AzTenant -ErrorAction SilentlyContinue)) {
        Connect-AzAccount | Out-Null
    }

    # Get an access token
    $token = (Get-AzAccessToken -ResourceUrl $uri).Token

    # Define common set of headers
    $global:baseHeaders = @{
        'Authorization'    = 'Bearer ' + $token
        'Accept'           = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }

    # Set baseURI
    $global:baseURI = $uri + 'api/data/v9.2/'
}


<#
.SYNOPSIS
Invokes a set of commands against the Dataverse Web API.

.DESCRIPTION
The Invoke-DataverseCommands function uses the Invoke-Command cmdlet to run a script block of commands against the Dataverse Web API. 
It handles any errors that may occur from the Dataverse API or the script itself.

.PARAMETER commands
The script block of commands to run against the Dataverse resource. This parameter is mandatory.

.EXAMPLE
Invoke-DataverseCommands -commands {
   # Get first account from Dataverse
   $accounts = (Get-Records `
      -setName 'accounts' `
      -query '?$select=name&$top=1').value

   $oldName = $accounts[0].name
   $newName = 'New Name'

   # Update the first account name to 'New Name'
   Set-ColumnValue `
      -setName 'accounts' `
      -id $accounts[0].accountid `
      -property 'name' `
      -value $newName

   Write-Host "First account name changed from '$oldName' to '$newName'"
}
This example invokes a script block that gets the first account from Dataverse and updates the name of the first account.
#>


function Invoke-DataverseCommands {
    param (
        [Parameter(Mandatory)] 
        $commands
    )
    try {
        Invoke-Command $commands -NoNewScope
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        Write-Host "An error occurred calling Dataverse:" -ForegroundColor Red
        $statuscode = [int]$_.Exception.StatusCode;
        $statusText = $_.Exception.StatusCode
        Write-Host "StatusCode: $statuscode ($statusText)"
        # Replaces escaped characters in the JSON
        [Regex]::Replace($_.ErrorDetails.Message, "\\[Uu]([0-9A-Fa-f]{4})", 
            { [char]::ToString([Convert]::ToInt32($args[0].Groups[1].Value, 16)) } )

    }
    catch {
        Write-Host "An error occurred in the script:" -ForegroundColor Red
        $_
    }
}

<#
.SYNOPSIS
Invokes a REST method with resilience to handle 429 errors.

.DESCRIPTION
The Invoke-ResilientRestMethod function uses the Invoke-RestMethod cmdlet to send an HTTP request to a RESTful web service. 
It handles any 429 errors (Too Many Requests) by retrying the request using the Retry-After header value as the retry interval. 
It also supports using a proxy if the $debug variable is set to true.

.PARAMETER request
A hashtable of parameters to pass to the Invoke-RestMethod cmdlet. This parameter is mandatory.

.PARAMETER returnHeader
A boolean value that indicates whether to return the response headers instead of the response body. The default value is false.

.EXAMPLE
See the functions in the TableOperations.ps1 file for examples of using this function.
#>

function Invoke-ResilientRestMethod {
    param (
        [Parameter(Mandatory)] 
        $request,
        [bool]
        $returnHeader
    )

    if ($debug) {
        $request.Add('Proxy', $proxyUrl)
    }
    try {
        Invoke-RestMethod @request -ResponseHeadersVariable rhv
        if ($returnHeader) {
            return $rhv
        }
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        $statuscode = $_.Exception.Response.StatusCode
        # 429 errors only
        if ($statuscode -eq 'TooManyRequests') {
            if (!$request.ContainsKey('MaximumRetryCount')) {
                $request.Add('MaximumRetryCount', 3)
                # Don't need - RetryIntervalSec
                # When the failure code is 429 and the response includes the Retry-After property in its headers, 
                # the cmdlet uses that value for the retry interval, even if RetryIntervalSec is specified
            }
            # Will attempt retry up to 3 times
            Invoke-RestMethod @request -ResponseHeadersVariable rhv
            if ($returnHeader) {
                return $rhv
            }
        }
        else {
            throw $_
        }
    }
    catch {
        throw $_
    }
}


<#
.SYNOPSIS
Gets a set of records from a Dataverse table.

.DESCRIPTION
The Get-Records function uses the Invoke-ResilientRestMethod function to send a GET request to the Dataverse API. 
It constructs the request URI by appending the entity set name and the query parameters to the base URI. 
It also adds the necessary headers to include annotations in the response.

.PARAMETER setName
The name of the entity set to retrieve records from. This parameter is mandatory.

.PARAMETER query
The query parameters to filter, sort, or select the records. This parameter is mandatory.

.EXAMPLE
(Get-Records -setName accounts -query '?$select=name&$top=10').value
This example gets the name of the first 10 accounts from Dataverse.


$accountContacts = (Get-Records `
   -setName 'accounts' `
   -query ('({0})/contact_customer_accounts?$select=fullname,jobtitle' `
      -f $accountId)).value

This example uses the query parameter to return a collection of contact records related to an account using the contact_customer_accounts relationship.

#>

function Get-Records {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $setName,
        [Parameter(Mandatory)] 
        [String] 
        $query
    )
    $uri = $baseURI + $setName + $query
    # Header for GET operations that have annotations
    $getHeaders = $baseHeaders.Clone()
    $getHeaders.Add('If-None-Match', $null)
    $getHeaders.Add('Prefer', 'odata.include-annotations="*"')
    $RetrieveMultipleRequest = @{
        Uri     = $uri
        Method  = 'Get'
        Headers = $getHeaders
    }
    Invoke-ResilientRestMethod $RetrieveMultipleRequest
}

<#
.SYNOPSIS
Creates a new record in a Dataverse table.

.DESCRIPTION
The New-Record function uses the Invoke-ResilientRestMethod function to send a POST request to the Dataverse Web API. 
It constructs the request URI by appending the entity set name to the base URI. 
It also adds the necessary headers and converts the body hashtable to JSON format. It returns the GUID ID value of the created record.

.PARAMETER setName
The name of the entity set to create a record in. This parameter is mandatory.

.PARAMETER body
A hashtable of attributes and values for the new record. This parameter is mandatory.

.EXAMPLE
$contactRafelShillo = @{
   'firstname' = 'Rafel'
   'lastname'  = 'Shillo'
}

$rafelShilloId = New-Record `
   -setName 'contacts' `
   -body $contactRafelShillo

This example creates a new contact record with the firstname 'Rafel' and the lastname 'Shillo'. It returns the GUID ID of the created record.
#>

function New-Record {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $setName,
        [Parameter(Mandatory)] 
        [hashtable]
        $body
    )

    $postHeaders = $baseHeaders.Clone()
    $postHeaders.Add('Content-Type', 'application/json')
   
    $CreateRequest = @{
        Uri     = $baseURI + $setName
        Method  = 'Post'
        Headers = $postHeaders
        Body    = ConvertTo-Json $body -Depth 5 # 5 should be enough for most cases, the default is 2.

    }
    $rh = Invoke-ResilientRestMethod -request $CreateRequest -returnHeader $true
    $url = $rh[1]['OData-EntityId']
    $selectedString = Select-String -InputObject $url -Pattern '(?<=\().*?(?=\))'
    return [System.Guid]::New($selectedString.Matches.Value.ToString())
}


<#
.SYNOPSIS
Gets a single record from a Dataverse table by its primary key value.

.DESCRIPTION
The Get-Record function uses the Invoke-ResilientRestMethod function to send a GET request to the Dataverse API. 
It constructs the request URI by appending the entity set name, the record ID, and the query parameters to the base URI. 
It also adds the necessary headers to include annotations in the response. It returns the record as an object.

.PARAMETER setName
The name of the entity set to retrieve the record from. This parameter is mandatory.

.PARAMETER id
The GUID of the record to retrieve. This parameter is mandatory.

.PARAMETER query
The query parameters to filter, expand, or select the record properties. This parameter is optional.

.EXAMPLE
   $retrievedRafelShillo1 = Get-Record `
      -setName 'contacts' `
      -id $rafelShilloId `
      -query '?$select=fullname,annualincome,jobtitle,description'

This example gets the fullname, annualincome, jobtitle, and description of the contact with the specified ID.
#>

function Get-Record {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $setName,
        [Parameter(Mandatory)] 
        [Guid] 
        $id,
        [String] 
        $query
    )
    $uri = $baseURI + $setName
    $uri = $uri + '(' + $id.Guid + ')' + $query
    $getHeaders = $baseHeaders.Clone()
    $getHeaders.Add('If-None-Match', $null)
    $getHeaders.Add('Prefer', 'odata.include-annotations="*"')
    $RetrieveRequest = @{
        Uri     = $uri
        Method  = 'Get'
        Headers = $getHeaders
    }
    Invoke-ResilientRestMethod $RetrieveRequest | Select-Object
}

<#
.SYNOPSIS
Gets the value of a single property from a Dataverse record.

.DESCRIPTION
The Get-ColumnValue function uses the Invoke-ResilientRestMethod function to send a GET request to the Dataverse API. 
It constructs the request URI by appending the entity set name, the record ID, and the property name to the base URI. 
It also adds the necessary headers to avoid caching. It returns the value of the property as a string.

.PARAMETER setName
The name of the entity set to retrieve the record from. This parameter is mandatory.

.PARAMETER id
The GUID of the record to retrieve. This parameter is mandatory.

.PARAMETER property
The name of the property to get the value from. This parameter is mandatory.

.EXAMPLE
$telephone1 = Get-ColumnValue `
   -setName 'contacts' `
   -id 9ec0b0ec-d6c3-4b8d-bd75-435723b49f84 `
   -property 'telephone1'

This example gets the telephone1 value of the contact record with the specified ID.
#>

function Get-ColumnValue {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $setName,
        [Parameter(Mandatory)] 
        [Guid] 
        $id,
        [String] 
        $property
    )
    $uri = $baseURI + $setName
    $uri = $uri + '(' + $id.Guid + ')/' + $property
    $headers = $baseHeaders.Clone()
    $headers.Add('If-None-Match', $null)
    $GetColumnValueRequest = @{
        Uri     = $uri
        Method  = 'Get'
        Headers = $headers
    }
    $value = Invoke-ResilientRestMethod $GetColumnValueRequest
    return $value.value
}


<#
.SYNOPSIS
Updates an existing record in a Dataverse table.

.DESCRIPTION
The Update-Record function uses the Invoke-ResilientRestMethod function to send a PATCH request to the Dataverse API. 
It constructs the request URI by appending the entity set name and the record ID to the base URI. 
It also adds the necessary headers and converts the body hashtable to JSON format. 
It uses the If-Match header to prevent creating a new record if the record ID does not exist.

.PARAMETER setName
The name of the entity set to update the record in. This parameter is mandatory.

.PARAMETER id
The GUID of the record to update. This parameter is mandatory.

.PARAMETER body
A hashtable of attributes and values for the updated record. This parameter is mandatory.

.EXAMPLE
$body = @{
   'annualincome' = 80000
   'jobtitle'     = 'Junior Developer'
}

# Update the record with the data
Update-Record `
   -setName 'contacts' `
   -id 9ec0b0ec-d6c3-4b8d-bd75-435723b49f84`
   -body $body

This example updates the annualincome and jobtitle of the contact with the specified ID.
#>


function Update-Record {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $setName,
        [Parameter(Mandatory)] 
        [Guid] 
        $id,
        [Parameter(Mandatory)] 
        [hashtable]
        $body
    )
    $uri = $baseURI + $setName
    $uri = $uri + '(' + $id.Guid + ')'
    # Header for Update operations
    $updateHeaders = $baseHeaders.Clone()
    $updateHeaders.Add('Content-Type', 'application/json')
    $updateHeaders.Add('If-Match', '*') # Prevent Create
    $UpdateRequest = @{
        Uri     = $uri
        Method  = 'Patch'
        Headers = $updateHeaders
        Body    = ConvertTo-Json $body
    }
    Invoke-ResilientRestMethod $UpdateRequest
}

<#
.SYNOPSIS
Sets the value of a single property for a Dataverse record.

.DESCRIPTION
The Set-ColumnValue function uses the Invoke-ResilientRestMethod function to send a PUT request to the Dataverse API. 
It constructs the request URI by appending the entity set name, the record ID, and the property name to the base URI. 
It also adds the necessary headers and converts the value to JSON format. 
It overwrites the existing value of the property with the new value.

.PARAMETER setName
The name of the entity set to update the record in. This parameter is mandatory.

.PARAMETER id
The GUID of the record to update. This parameter is mandatory.

.PARAMETER property
The name of the property to set the value for. This parameter is mandatory.

.PARAMETER value
The new value for the property. This parameter is mandatory.

.EXAMPLE
Set-ColumnValue `
   -setName 'contacts' `
   -id 9ec0b0ec-d6c3-4b8d-bd75-435723b49f84 `
   -property 'telephone1' `
   -value '555-0105'

This example sets the telephone1 column value of the contact with the specified ID to 555-0105.
#>


function Set-ColumnValue {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $setName,
        [Parameter(Mandatory)] 
        [Guid] 
        $id,
        [Parameter(Mandatory)] 
        [string]
        $property,
        [Parameter(Mandatory)] 
        $value
    )
    $uri = $baseURI + $setName
    $uri = $uri + '(' + $id.Guid + ')' + '/' + $property
    $headers = $baseHeaders.Clone()
    $headers.Add('Content-Type', 'application/json')
    $body = @{
        'value' = $value
    }
    $SetColumnValueRequest = @{
        Uri     = $uri
        Method  = 'Put'
        Headers = $headers
        Body    = ConvertTo-Json $body
    }
    Invoke-ResilientRestMethod $SetColumnValueRequest
}




function Set-FileColumn {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $setName,
        [Parameter(Mandatory)] 
        [Guid] 
        $id,
        [Parameter(Mandatory)] 
        [string]
        $property,
        [Parameter(Mandatory)] 
        $filename,
        [Parameter(Mandatory)] 
        $byteArray
    )
    $uri = $baseURI + $setName
    $uri = $uri + '(' + $id.Guid + ')' + '/' + $property + "?x-ms-file-name=$filename"

    Write-Host $uri
    $headers = $baseHeaders.Clone()
    $headers.Add('Content-Type', 'application/octet-stream')
    #$headers.Add('x-ms-file-name', $filename)

    $SetColumnValueRequest = @{
        Uri     = $uri
        Method  = 'Patch'
        Headers = $headers
        Body    = $byteArray
    }
    Invoke-ResilientRestMethod $SetColumnValueRequest
}

function Set-FileColumnBase64 {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $setName,
        [Parameter(Mandatory)] 
        [Guid] 
        $id,        
        [Parameter(Mandatory)] 
        $filename,
        [Parameter(Mandatory)] 
        [string]
        $property,
        [Parameter(Mandatory)] 
        $base64Content
    )

    $byteArray = [System.Convert]::FromBase64String($base64Content)

    Set-FileColumn -setName $setName -id $id -property $property -filename $filename -byteArray $byteArray
}

<#
.SYNOPSIS
Adds a record to a collection-valued navigation property of another record.

.DESCRIPTION
The Add-ToCollection function uses the Invoke-ResilientRestMethod function to send a POST request to the Dataverse API. 
It constructs the request URI by appending the target entity set name, the target record ID, and the collection name to the base URI. 
It also adds the necessary headers and converts the record URI to JSON format. 
It creates a reference between the target record and the record to be added to the collection.

.PARAMETER targetSetName
The name of the entity set that contains the target record. This parameter is mandatory.

.PARAMETER targetId
The GUID of the target record. This parameter is mandatory.

.PARAMETER collectionName
The name of the collection-valued navigation property of the target record. This parameter is mandatory.

.PARAMETER setName
The name of the entity set that contains the record to be added to the collection. This parameter is mandatory.

.PARAMETER id
The GUID of the record to be added to the collection. This parameter is mandatory.

.EXAMPLE
Add-ToCollection `
   -targetSetName 'accounts' `
   -targetId 9ec0b0ec-d6c3-4b8d-bd75-435723b49f84 `
   -collectionName 'contact_customer_accounts' `
   -setName 'contacts' `
   -id 5d68b37f-aae9-4cd6-8b94-37d6439b2f34

This example adds the contact with the specified ID to the contact_customer_accounts collection of the account with the specified ID.
#>


function Add-ToCollection {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $targetSetName,
        [Parameter(Mandatory)] 
        [Guid] 
        $targetId,
        [Parameter(Mandatory)] 
        [string]
        $collectionName,
        [Parameter(Mandatory)] 
        [String] 
        $setName,
        [Parameter(Mandatory)] 
        [Guid] 
        $id
    )
    $uri = '{0}{1}({2})/{3}/$ref' `
        -f $baseURI, $targetSetName, $targetId, $collectionName

    $headers = $baseHeaders.Clone()
    $headers.Add('Content-Type', 'application/json')

    # Must use absolute URI
    $recordUri = '{0}{1}({2})' `
        -f $baseURI, $setName, $id

    $body = @{
        '@odata.id' = $recordUri
    }
    $AssociateRequest = @{
        Uri     = $uri
        Method  = 'Post'
        Headers = $headers
        Body    = ConvertTo-Json $body
    }
    Invoke-ResilientRestMethod $AssociateRequest
}

<#
.SYNOPSIS
Removes a record from a collection-valued navigation property of another record.

.DESCRIPTION
The Remove-FromCollection function uses the Invoke-ResilientRestMethod function to send a DELETE request to the Dataverse API. 
It constructs the request URI by appending the target entity set name, the target record ID, the collection name, and the record ID to the base URI. 
It also adds the necessary headers. It deletes the reference between the target record and the record to be removed from the collection.

.PARAMETER targetSetName
The name of the entity set that contains the target record. This parameter is mandatory.

.PARAMETER targetId
The GUID of the target record. This parameter is mandatory.

.PARAMETER collectionName
The name of the collection-valued navigation property of the target record. This parameter is mandatory.

.PARAMETER id
The GUID of the record to be removed from the collection. This parameter is mandatory.

.EXAMPLE
Remove-FromCollection `
   -targetSetName 'accounts' `
   -targetId 9ec0b0ec-d6c3-4b8d-bd75-435723b49f84 `
   -collectionName 'contact_customer_accounts' `
   -id 5d68b37f-aae9-4cd6-8b94-37d6439b2f34
This example removes the contact with the specified ID from the contact_customer_accounts collection of the account with the specified ID.
#>


function Remove-FromCollection {
    param (
        [Parameter(Mandatory)] 
        [String] 
        $targetSetName,
        [Parameter(Mandatory)] 
        [Guid] 
        $targetId,
        [Parameter(Mandatory)] 
        [string]
        $collectionName,
        [Parameter(Mandatory)] 
        [Guid] 
        $id
    )
    $uri = '{0}{1}({2})/{3}({4})/$ref' `
        -f $baseURI, $targetSetName, $targetId, $collectionName, $id

    $DisassociateRequest = @{
        Uri     = $uri
        Method  = 'Delete'
        Headers = $baseHeaders
    }
    Invoke-ResilientRestMethod $DisassociateRequest
}

<#
.SYNOPSIS
Deletes a record from a Dataverse table.

.DESCRIPTION
The Remove-Record function uses the Invoke-ResilientRestMethod function to send a DELETE request to the Dataverse API. 
It constructs the request URI by appending the entity set name and the record ID to the base URI. 
It also adds the necessary headers. It deletes the record with the specified ID from the table.

.PARAMETER setName
The name of the entity set to delete the record from. This parameter is mandatory.

.PARAMETER id
The GUID of the record to delete. This parameter is mandatory.

.EXAMPLE
Remove-Record `
   -setName accounts `
   -id 9ec0b0ec-d6c3-4b8d-bd75-435723b49f84
This example deletes the account with the specified ID from the Dataverse table.
#>

function Remove-Record {
    param (
        [Parameter(Mandatory)] 
        [String]
        $setName,
        [Parameter(Mandatory)] 
        [Guid] 
        $id
    )
    $uri = $baseURI + $setName
    $uri = $uri + '(' + $id.Guid + ')'
    $DeleteRequest = @{
        Uri     = $uri
        Method  = 'Delete'
        Headers = $baseHeaders
    }
    Invoke-ResilientRestMethod $DeleteRequest
}