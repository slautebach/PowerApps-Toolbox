
Import-Module "$PSScriptRoot\Functions.psm1"  -DisableNameChecking 

Load-Module powershell-yaml

$global:solutionMasterPath = "$PSScriptRoot\..\..\SolutionMaster"

function Write-SolutionFile([xml]$xmlContent, [string]$outFile, [switch] $sort){

    [System.IO.FileInfo] $outFileInfo = New-Object System.IO.FileInfo($outFile)
    if ($sort){
        Sort-Xml -xml $xmlContent
    }
    $outDirectory =  $outFileInfo.Directory.FullName
    # create full path to file if it doesn't exist.
    if (!(Test-Path $outDirectory)){
        Write-Host "Creating directory: $outDirectory"
        New-Item -ItemType Directory -Force -Path $outDirectory
    }
    $content = $xmlContent.OuterXml
    $content = Format-Xml -Xml $content
    # Write the content to disk
    Write-Host "Writing solution changed file: $outFile"
    $content | Out-File -Encoding "UTF8" -LiteralPath $outFile
}

function Process-SolutionFile($solutionFile, [switch] $sort){

    
    # get the realtive file to the solution file
    $solutionRelativePath = $solutionFile.FullName.Replace($global:solutionFilesPath, "")


    # Load the Solution part xml file, and pretty format the xml
    [xml]$solutionFileXml = Get-Content $solutionFile.FullName
    $solutionFileXml = Format-Xml -Xml $solutionFileXml


    # create the output file
    Write-SolutionFile -xmlContent $solutionFileXml -outFile "$($global:solutionMasterPath)\$solutionRelativePath" -sort:$sort
}

function Process-WebResource($solutionFile){
    
    # get the realtive file to the solution file
    $solutionRelativePath = $solutionFile.FullName.Replace($global:solutionFilesPath, "")
    if ($solutionRelativePath -like "WebResources\north52_\formula\*"){
        Process-WebResource-North52-Formula ($solutionFile)
        return
    }

    if ($solutionRelativePath -like "WebResources\north52_\xcache\*"){
        Process-WebResource-North52-XCache ($solutionFile)
        return
    }
    #Write-Host "Not Working with file: $solutionRelativePath"
    # Handle Other Web Resrouces
}




$n52Mapping = @{}
$n52Mapping["Formula Type"] = @{}
$n52Mapping["Formula Type"]["217890021"] = "Action"
$n52Mapping["Formula Type"]["217890005"] = "Auto Number"
$n52Mapping["Formula Type"]["217890000"] = "Calculated Field"
$n52Mapping["Formula Type"]["217890006"] = "Calculated Hyperlink"
$n52Mapping["Formula Type"]["217890014"] = "ClientSide - Calculation"
$n52Mapping["Formula Type"]["217890015"] = "ClientSide - Perform Action"
$n52Mapping["Formula Type"]["217890017"] = "Command Console"
$n52Mapping["Formula Type"]["217890011"] = "Dialog\Workflow Calculation (Deprecated)"
$n52Mapping["Formula Type"]["217890012"] = "Dialog\Workflow Perform Action (Deprecated)"
$n52Mapping["Formula Type"]["217890007"] = "Display Alert (Deprecated)"
$n52Mapping["Formula Type"]["217890022"] = "Library Calculation"
$n52Mapping["Formula Type"]["217890018"] = "N:N Associate"
$n52Mapping["Formula Type"]["217890019"] = "N:N Disassociate"
$n52Mapping["Formula Type"]["217890009"] = "Notification Critical (Deprecated)"
$n52Mapping["Formula Type"]["217890010"] = "Notification Information (Deprecated)"
$n52Mapping["Formula Type"]["217890008"] = "Notification Warning (Deprecated)"
$n52Mapping["Formula Type"]["217890016"] = "Process Genie"
$n52Mapping["Formula Type"]["217890013"] = "Save - Perform Action"
$n52Mapping["Formula Type"]["217890002"] = "Save - To Children (Deprecated)"
$n52Mapping["Formula Type"]["217890003"] = "Save - To Current Record"
$n52Mapping["Formula Type"]["217890001"] = "Save - To Parent"
$n52Mapping["Formula Type"]["217890020"] = "SmartFlow"
$n52Mapping["Formula Type"]["217890004"] = "Validation"

$n52Mapping["Event"] = @{}
$n52Mapping["Event"]["217890000"] = "Create"
$n52Mapping["Event"]["217890005"] = "Create & Delete"
$n52Mapping["Event"]["217890002"] = "Create & Update"
$n52Mapping["Event"]["217890004"] = "Create, Update & Delete"
$n52Mapping["Event"]["217890003"] = "Delete"
$n52Mapping["Event"]["217890001"] = "Update"
$n52Mapping["Event"]["217890006"] = "Update & Delete"

$n52Mapping["Stage"] = @{}
$n52Mapping["Stage"]["217890000"] = "Pre-Validation  (Synchronous)"
$n52Mapping["Stage"]["217890002"] = "Pre-Operation  (Synchronous)"
$n52Mapping["Stage"]["217890001"] = "Post-Operation (Synchronous)"
$n52Mapping["Stage"]["217890003"] = "Post-Operation (Asynchronous)"

$n52Mapping["Mode"] = @{}
$n52Mapping["Mode"]["217890001"] = "Client Side"
$n52Mapping["Mode"]["217890000"] = "Client Side &amp; Server Side"
$n52Mapping["Mode"]["217890002"] = "Server Side"

$n52Mapping["Execute As"] = @{}
$n52Mapping["Execute As"]["217890000"] = "Calling User"
$n52Mapping["Execute As"]["217890002"] = "Server to Server Authentication User"
$n52Mapping["Execute As"]["217890001"] = "System User (Administrator)"

$n52Mapping["Execution Process"] = @{}
$n52Mapping["Execution Process"]["217890000"] = "Dynamics Sandbox"
$n52Mapping["Execution Process"]["217890001"] = "Azure Process Genie - Sync (Http Trigger)"
$n52Mapping["Execution Process"]["217890002"] = "Azure Process Genie - Async (Service Bus Trigger)"
$n52Mapping["Execution Process"]["217890003"] = "Azure Process Genie - Timer"

$n52Mapping["Display Format"] = @{}
$n52Mapping["Display Format"]["217890006"] = "Boolean"
$n52Mapping["Display Format"]["217890002"] = "Currency"
$n52Mapping["Display Format"]["217890004"] = "Date"
$n52Mapping["Display Format"]["217890001"] = "Date &amp; Time"
$n52Mapping["Display Format"]["217890003"] = "Decimal"
$n52Mapping["Display Format"]["217890000"] = "String"
$n52Mapping["Display Format"]["217890005"] = "Whole Number"

$n52Mapping["Query Type"] = @{}
$n52Mapping["Query Type"]["217890000"] = "Source"
$n52Mapping["Query Type"]["217890001"] = "Target"

function Load-N52-Worksheet($worksheetFile){
    $n52SheetDetail = [Ordered]@{}
    [xml]$xml = Get-Content $worksheetFile -Encoding Unicode
    for ($i = 0; $i -lt $xml.Workbook.Worksheet.Table.Row[0].Cell.Length; $i++) {
        $key = $xml.Workbook.Worksheet.Table.Row[0].Cell[$i].InnerText
        $strValue = $xml.Workbook.Worksheet.Table.Row[1].Cell[$i].Data.InnerXml
        
        $value = $strValue
        if (IsNumeric $strValue ){
            $value = [int] $strValue
        }

        $n52SheetDetail[$key] = $value

        if ($n52Mapping.ContainsKey($key) -and $n52Mapping[$key].ContainsKey($strValue)){
            $n52SheetDetail[$key] = @{}
            $n52SheetDetail[$key].Name = $n52Mapping[$key][$strValue]
            $n52SheetDetail[$key].Value = $value
        }
    }
    Write-Output $n52SheetDetail
}

function Process-WebResource-North52-Formula($solutionFile){
    
    $north52DestinationPath = "$($global:solutionMasterPath)\North52\formula"
    if (!(Test-Path $north52DestinationPath)){
        Write-Host "Creating directory: $north52DestinationPath"
        New-Item -ItemType Directory -Force -Path $north52DestinationPath
    }

    # get the realtive file to the solution file
    $solutionRelativePath = $solutionFile.FullName.Replace($global:solutionFilesPath, "")
    
    if ($solutionFile.Name -notlike "f.*.data.xml"){
        #Write-Host "$solutionRelativePath Not a formula file, skipping"
        return
    }
    $formulaFile = $solutionFile.Name -replace ".data.xml", ""
    $formulaFilePath = "$($solutionFile.Directory)\$formulaFile"
    
    $id = $formulaFile -replace "f.", ""

    Write-Host "Formula File: $formulaFilePath"
    $formulaDetail = Load-N52-Worksheet -worksheetFile $formulaFilePath
    
    # extract the name from the work sheet
    $name = $formulaDetail.Name

    $formulaContent = $formulaDetail["Formula Description"]
    $formulaContent = $formulaContent.Trim()
    $formulaDetail.Remove("Formula Description")
  
    $formulaBaseName = ConvertInvalidFileNames -fileName $formulaDetail.Name

    $formulaCode = $solutionFile.Directory.Name
    $entity = $solutionFile.Directory.Parent.Name
    $path = "$north52DestinationPath\$entity\$formulaCode"
      
    Write-Host "Deleting Formula: $formulaCode, Path: $path"  

     if (Test-Path $path){
        # Delete any exiting files related to the record.  That is all files 
        # that have the record guid  in it's name.  This will take care of renames.
        Remove-Item -Path $path -Force -Recurse
    }
    Write-Host "Creating Formula Code: $path"
    New-Item -ItemType Directory -Force -Path $path

    Write-Host "Updating N52 formula: $path\$formulaBaseName.n52f"
    $formulaContent | Out-File -Encoding "UTF8" -LiteralPath "$path\$formulaBaseName.n52f"
    Write-Host "Updating N52 formula metadata: $path\$formulaBaseName.yml"
    $formulaDetail | ConvertTo-Yaml | Out-File -Encoding "UTF8" -LiteralPath "$path\$formulaBaseName.yml"

    if ($formulaContent.StartsWith("DecisionTable(")){
        # TDO 
        #$startPos = $formulaContent.IndexOf("/*") + 2
        #$lastPos = $formulaContent.LastIndexOf("*/")
        #$dtRawJson = $formulaContent.SubString($startPos, $lastPos-$startPos)
        #$dtJson = $dtRawJson | ConvertFrom-Json
        #$dtJson.sheets.DecisionTable.data.dataTable
        #Write-Host $dtJson
        #exit
    }
    

    $formulaDetailFiles = Get-ChildItem $solutionFile.Directory.FullName -Recurse -file -Include "fd.*" 

    foreach ($fd in $formulaDetailFiles){
        
        if ($fd.FullName.EndsWith(".data.xml")){
            # Found the Data.xml file, ignore
            continue;
        }
        $formulaFetchDetail = Load-N52-Worksheet -worksheetFile $fd
        
        $query = $formulaFetchDetail.Query
        $formulaFetchDetail.Remove("Query")

        $fetchBaseName = ConvertInvalidFileNames -fileName    $formulaFetchDetail.Name
        Write-Host "Updating N52 Fetch: $path\$fetchBaseName"
        $formulaFetchDetail | ConvertTo-Yaml | Out-File -Encoding "UTF8" -LiteralPath "$path\$fetchBaseName.fetch.yml"
        $queryXml = [xml]$query
        $query =  Format-XML -xml $queryXml
        $query | Out-File -Encoding "UTF8" -LiteralPath "$path\$fetchBaseName.fetch.xml"
    }
}


function Process-WebResource-North52-XCache($solutionFile){
    
    # get the realtive file to the solution file
    $solutionRelativePath = $solutionFile.FullName.Replace($global:solutionFilesPath, "")
    
    if ($solutionFile.Name -notlike "x.*.data.xml"){
        Write-Host "$solutionRelativePath Not a formula file, skipping"
        return
    }
    
    $north52DestinationPath = "$($global:solutionMasterPath)\North52\xcache"
    if (!(Test-Path $north52DestinationPath)){
        Write-Host "Creating directory: $north52DestinationPath"
        New-Item -ItemType Directory -Force -Path $north52DestinationPath
    }

    
    $xcacheFile = $solutionFile.Name -replace ".data.xml", ""
    $xcacheFilePath = "$($solutionFile.Directory)\$xcacheFile"
    
    $id = $xcacheFile -replace "x.", ""

    Write-Host "Formula File: $xcacheFilePath"
    $xcacheDetail = Load-N52-Worksheet -worksheetFile $xcacheFilePath
    
    # extract the name from the work sheet
    $name = $xcacheDetail["Base Key"]
    
    $xcacheMetaDataFileName = ConvertInvalidFileNames -fileName "$name.$id.yml"  
    $xcacheCode = $solutionFile.Directory.Name
    $path = "$north52DestinationPath\$xcacheCode"

    Write-Host "Deleting XCache: $xcacheCode With ID: '$id', Name: $name"  
    # Delete any exiting files related to the record.  That is all files 
    # that have the record guid  in it's name.  This will take care of renames.
    Get-ChildItem "$north52DestinationPath" -Filter "*$id*" -Recurse | Remove-Item

   
    if (!(Test-Path $path)){
        Write-Host "Creating directory: $path"
        New-Item -ItemType Directory -Force -Path $path
    }
    Write-Host "Updating XCache formula metadata: $path\$xcacheMetaDataFileName"
    $xcacheDetail | ConvertTo-Yaml | Out-File -Encoding "UTF8" -LiteralPath "$path\$xcacheMetaDataFileName"
}

function Process-Entity($entityFile){



    $entityRelativeFile = $entityFile.FullName.Replace("$($global:solutionFilesPath)Entities\", "")
    $entityFileParts = $entityRelativeFile -split "\\"
    $entityLogicalName = $entityFileParts[0]
    
    $outRelativePath = $entityFile.Directory.FullName.Replace($global:solutionFilesPath, "")
    $outputPath = "$($global:solutionMasterPath)\$outRelativePath";
    
    # make sure the output path exists
    mkdir $outputPath -Force -ErrorAction SilentlyContinue | Out-Null
    
    # get the full name of the path 
    $outputPath =  (Get-Item $outputPath).FullName

    # Load the Solution part xml file, and pretty format the xml
    [xml]$solutionFileXml = Get-Content $entityFile.FullName
    $id = ""
    $name = $entityFile.Basename
    $sort = $false
    if ($entityFileParts.Length -eq 3){
        # Saved Query
        $nodeName = $solutionFileXml | Select-Xml -XPath "//savedqueries/savedquery/LocalizedNames/LocalizedName[@languagecode=1033]/@description"
        $nodeId = $solutionFileXml | Select-Xml -XPath "//savedqueries/savedquery/savedqueryid"        
        if ($nodeName -eq $null){
            $nodeName = $solutionFileXml | Select-Xml -XPath "//savedquery/LocalizedNames/LocalizedName[@languagecode=1033]/@description"
            $nodeId = $solutionFileXml | Select-Xml -XPath "//savedquery/savedqueryid"        
        }
        $name = $nodeName.Node.Value
        
        $id = $nodeId.Node.InnerText
    }
    elseif ($entityFileParts.Length -eq 4){
        
        #Entity Form

        $nodeName = $solutionFileXml | Select-Xml -XPath "//forms/systemform/LocalizedNames/LocalizedName[@languagecode=1033]/@description"
        $nodeId = $solutionFileXml | Select-Xml -XPath "//forms/systemform/formid"        
        if ($nodeName -eq $null){
            $nodeName = $solutionFileXml | Select-Xml -XPath "//systemform/LocalizedNames/LocalizedName[@languagecode=1033]/@description"
            $nodeId = $solutionFileXml | Select-Xml -XPath "//systemform/formid"        
        }
        $name = $nodeName.Node.Value
        
        $id = $nodeId.Node.InnerText
    }
    elseif ($entityFileParts[1] -eq "Entity.xml"){
        $sort = $true
        $attributes = $solutionFileXml.SelectSingleNode("//Entity/EntityInfo/entity/attributes")
        #remove attributes from entity info
        $attributes.ParentNode.RemoveChild($attributes);

        # write each attribute out as its own file.
        foreach ($attribNode in $attributes.ChildNodes){
            $attributeLogicalName = $attribNode.PhysicalName
            Write-SolutionFile -xmlContent $attribNode.OuterXml -outFile "$outputPath\Attributes\$attributeLogicalName.xml" -sort
        }
    }

    $fileName = "$name$($entityFile.Extension)"
    if ($id -ne $null -and $id -ne ""){
        $fileName = "$name.$id$($entityFile.Extension)"
        Write-Host "Deleting files with id: '$id'"
        # Delete any exiting files related to the record.  That is all files 
        # that have the record guid  in it's name.  This will take care of renames.
        Get-ChildItem $global:solutionMasterPath -Filter "*$id*" -Recurse | Remove-Item
    }
    $fileName = ConvertInvalidFileNames -fileName $fileName
   
    Write-Host "Entity File: $outputPath\$fileName"
    # create the output file
    Write-SolutionFile -xmlContent $solutionFileXml -outFile "$outputPath\$fileName" -sort:$sort

}

function Process-Solution-Folder(){
    param(
        [string]$solutionFilesPath #The folder to extract the CRM solution
    )
    

    Write-Host "Process Solution Folder: $solutionFilesPath"
    # Correct any double slashes causing errors with the path.
    $solutionFilesPath = (Get-Item $solutionFilesPath.Replace("\\", "\")).FullName

    $global:solutionFilesPath = $solutionFilesPath

    Write-Host $global:solutionFilesPath
    Write-Host $global:solutionMasterPath


    if (!(Test-Path $global:solutionMasterPath)){
        New-Item -ItemType Directory -Force -Path $global:solutionMasterPath
    }

    # Load all new solution files
    Write-Host "Loading Files From: $solutionFilesPath"
    $solutionFiles = Get-ChildItem "$solutionFilesPath" -recurse -file -Include "*.xml","*.xsl" 
    
    # for each file process them.
    foreach ($solutionFile in $solutionFiles){
        #Write-Host "File: $($solutionFile.FullName)"
        if ($solutionFile.FullName.EndsWith(".data.xml")){
            # Found the Data.xml file, ignore
            #continue;
        }

        Write-Host "Processing Solution File: $solutionFile"
        $directory = $solutionFile.Directory.FullName


        $regexSolutionFolder = $solutionFilesPath.Replace("\", "/")
        $regexSolutionFile = $solutionFile.FullName.Replace("\", "/")

        if ($regexSolutionFolder.EndsWith("/"))
        {
            $regexSolutionFolder = $regexSolutionFolder.Substring(0, $regexSolutionFolder.Length-1)
        }
        $regexSolutionFile =  $regexSolutionFile -replace "$regexSolutionFolder", ""

        $match = $regexSolutionFile | Select-String -Pattern "^/(?<component>[\w]+)/(?<file>.*)"
   
    
        $solutionComponent =  $match.Matches[0].Groups['component'].Value
        $solutionComponentFile = $match.Matches[0].Groups['file'].Value

        switch ($solutionComponent){
            "Entities" {
                Process-Entity $solutionFile;
                break;
            }
            "WebResources"{
                Process-WebResource -solutionFile $solutionFile
            }
            "Other" {
                # Process Relationship Files.
                if ($solutionComponentFile -like "Relationships/*"){
                    Process-SolutionFile $solutionFile -sort
                } 
                break;
            }       
            default {
                Process-SolutionFile $solutionFile -sort
                break;
            }
        }
    }
}

Export-ModuleMember -Function *