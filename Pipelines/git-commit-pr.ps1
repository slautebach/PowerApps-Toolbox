<#
Commits the changes and creates a pull requst
#>
param(
	# the name of the solution project for the Pull Request
	[string] $SolutionName,

	# System access tokent for Dev Ops to puch the git chagnes
	[string] $SystemAccessToken = $ENV:SYSTEM_ACCESSTOKEN,       

	# person who the commit as reqeusted for      
	[string] $RequestedFor = $ENV:BUILD_REQUESTEDFOR,

	# email of the commit who it was requested for
	[string] $RequestedForEmail = $ENV:BUILD_REQUESTEDFOREMAIL,

	# the source branch, where to commit the changes to.
	[string] $targetBranch = $ENV:BUILD_SOURCEBRANCH,

	# Repository id
	[string] $RepositoryId = $ENV:BUILD_REPOSITORY_ID,

	# Project Url
	[string] $devOpsProjectUrl = $ENV:BUILD_REPOSITORY_URI
) 


# remove the refs/heads/ frome the source branch
$targetBranch = $targetBranch.Replace("refs/heads/", "")
$prTargetBranch = $targetBranch.Replace("/", "-")
$prBranch = "prs/$prTargetBranch-$SolutionName"


# if we the build service
if (!$RequestedForEmail){
	$RequestedFor = "DevOps Automated Build"
	$RequestedForEmail = "builds@devops.com"
}
Write-Host "Config User Email: $RequestedForEmail"
Write-Host "Config User: $RequestedFor"
# configure git for the commit
git config --global user.email "$RequestedForEmail"
git config --global user.name "$RequestedFor"


$commitMessage = "Changes for: $targetBranch to Solution: '$SolutionName' requested by $RequestedFor <$RequestedForEmail>"


# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error Setting config"
} 

# change directory to the root source
cd "$PSScriptRoot\..\"


Write-Host "Adding files with 'git add --all'"
# add all new files to the branch
git add --all

# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error Adding files"
} 

Write-Host "Committing all files"
git commit -m "automated checkin from DevOps Requested for: $RequestedFor"   

# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error Commtting files"
} 


Write-Host "git status"
git status



Write-Host "Pushing changes to branch"
if ($SystemAccessToken){
	Write-Host "Using command git -c http.extraheader='AUTHORIZATION: bearer token' push --force origin '$prBranch'"
	# Push the new changes to the branch
	git -c http.extraheader="AUTHORIZATION: bearer $SystemAccessToken" push --force origin "$prBranch"
} else {
	Write-Host "Using command (non-access token) git push --force origin '$prBranch'"
	# Push the new changes to the branch
	git -c http.extraheader="AUTHORIZATION: bearer $SystemAccessToken" push --force origin "$prBranch"
}

# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error Pushing change to origin $prBranch"
} 


############################################################################################################################################
# Create Pull Request - https://docs.microsoft.com/en-us/rest/api/azure/devops/git/pull%20requests/create?view=azure-devops-rest-7.0
############################################################################################################################################


# Header
$headers = @{}

if ($SystemAccessToken){
	$headers.Authorization="Bearer $SystemAccessToken";
}

$PR=@{
  sourceRefName="refs/heads/$prBranch"
  targetRefName="refs/heads/$targetBranch"
  title= "$commitMessage"
  description="$commitMessage"
  isDraft=$false
}

Write-Host ""
Write-Host "=============================================================="
Write-Host "Create/Update Pull Request"
Write-Host "=============================================================="
# Check if the PR already exists
$getUrl = "$devOpsProjectUrl/_apis/git/repositories/$RepositoryId/pullrequests?searchCriteria.status=active&searchCriteria.sourceRefName=$($PR.sourceRefName)&searchCriteria.targetRefName=$($PR.targetRefName)&api-version=7.0"
Write-Host "Get List of existing Pull Requests Url: $getUrl"
$result = Invoke-RestMethod -Headers $headers -Uri $getUrl -Method GET -ContentType "application/json"
Write-Host $result
Write-Host $result.Count

if ($result.Count -gt 0){
    Write-Host "Pull Request already exists, it has been updated, via the commit."
    exit;
}

Write-Host "Creating Pull Request ...."

$postURL = "$devOpsProjectUrl/_apis/git/repositories/$RepositoryId/pullrequests?api-version=7.0"
Write-Host "PostURL: $postURL"

$prjson = $PR | ConvertTo-Json
Write-Host "JSON Post Body:"
Write-Host $prjson

# https://dev.azure.com/{organization}/{project}/_apis/git/repositories/{repositoryId}/pullrequests?api-version=7.0
$result = Invoke-RestMethod -Headers $headers -Uri $postURL  -Method POST -Body $prjson -ContentType "application/json" 

Write-Host ""
Write-Host "Result:"
Write-Host $result