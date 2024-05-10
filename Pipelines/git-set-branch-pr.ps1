<#
Checks out and configures the branch to do a pull request
#>
param(
		# the name of the solution project for the Pull Request
	[string] $SolutionName = "",

	#default list of reviewers to assin to the PR.
	[string] $reviewerEmailList= "",

	# System access tokent for Dev Ops to puch the git chagnes
	[string] $SystemAccessToken = $ENV:SYSTEM_ACCESSTOKEN,       

	# person who the commit as reqeusted for      
	[string] $RequestedFor = $ENV:BUILD_REQUESTEDFOR,

	# email of the commit who it was requested for
	[string] $RequestedForEmail = $ENV:BUILD_REQUESTEDFOREMAIL,

	# the source branch, where to commit the changes to.
	[string] $targetBranch = $ENV:BUILD_SOURCEBRANCH
) 

# remove the refs/heads/ frome the source branch
$targetBranch = $targetBranch.Replace("refs/heads/", "")
$prTargetBranch = $targetBranch.Replace("/", "-")
$prBranch = "prs/$prTargetBranch-$SolutionName"

#####################################
# configure git for the commit
#####################################
# if we the build service
# if we the build service
if (!$RequestedForEmail){
	$RequestedFor = "DevOps Automated Build"
	$RequestedForEmail = "builds@cfmws.com"
}
Write-Host "Config User Email: $RequestedForEmail"
Write-Host "Config User: $RequestedFor"
# configure git for the commit
git config --global user.email "$RequestedForEmail"
git config --global user.name "$RequestedFor"

# change directory to the root source
cd "$PSScriptRoot\..\"

Write-Host "Git Fetch"
if ($SystemAccessToken){
	git -c http.extraheader="AUTHORIZATION: bearer $SystemAccessToken" fetch
} else {
	git fetch
}

# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error fetching"
} 


Write-Host "Checking out: $targetBranch"
git checkout $targetBranch

# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error checking out $targetBranch"
} 


# Hard reset so we can safely switch/branch
git reset --hard

# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error resetting"
} 

Write-Host "branching $targetBranch => $prBranch"
git branch -f $prBranch

# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error branching $targetBranch => $prBranch"
} 


Write-Host "switching to branch: $prBranch"
git switch $prBranch

# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error switching to $prBranch"
} 


Write-Host "git status"
git status

# Check git last error
if ($LastExitCode -ne 0 ){
	throw "Error getting git status"
} 