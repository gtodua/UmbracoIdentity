param (
	[Parameter(Mandatory=$true)]
	[ValidatePattern("^\d+\.\d+\.(?:\d+\.\d+$|\d+$)|^\d+\.\d+\.\d+-(\w|-|\.)+$")]
	[string]
	$ReleaseVersionNumber,
	[Parameter(Mandatory=$false)]
	[string]
	[AllowEmptyString()]
	$PreReleaseName,
	[Parameter(Mandatory=$false)]
	[int]
	$IsBuildServer = 0

)

if([string]::IsNullOrEmpty($PreReleaseName) -And $ReleaseVersionNumber.Contains("-"))
{	
	$parts = $ReleaseVersionNumber.Split("-")
	$ReleaseVersionNumber = $parts[0]
	$PreReleaseName = "-" + $parts[1]
	Write-Host "Version parts split: ($ReleaseVersionNumber) and ($PreReleaseName)"
}

$PSScriptFilePath = (Get-Item $MyInvocation.MyCommand.Path);
$RepoRoot = (get-item $PSScriptFilePath).Directory.Parent.FullName;
$SolutionRoot = Join-Path -Path $RepoRoot "src";

#trace
"Solution Root: $SolutionRoot"

$BuildFolder = Join-Path -Path $RepoRoot -ChildPath "build";
# Make sure we don't have a release folder for this version already
$ReleaseFolder = Join-Path -Path $BuildFolder -ChildPath "Release";
if ((Get-Item $ReleaseFolder -ErrorAction SilentlyContinue) -ne $null)
{
	Write-Warning "$ReleaseFolder already exists on your local machine. It will now be deleted."
	Remove-Item $ReleaseFolder -Recurse
}
New-Item $ReleaseFolder -Type directory

# Go get nuget.exe if we don't hae it
$NuGet = "$BuildFolder\nuget.exe"
$FileExists = Test-Path $NuGet 
If ($FileExists -eq $False) {
	#$SourceNugetExe = "http://nuget.org/nuget.exe"
	$SourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
	Invoke-WebRequest $SourceNugetExe -OutFile $NuGet
}

if ($IsBuildServer -eq 1) {
	$MSBuild = "MSBuild.exe"
}
else {
	# ensure we have vswhere
	New-Item "$BuildFolder\vswhere" -type directory -force
	$vswhere = "$BuildFolder\vswhere.exe"
	if (-not (test-path $vswhere))
	{
	   Write-Host "Download VsWhere..."
	   $path = "$BuildFolder\tmp"
	   &$nuget install vswhere -OutputDirectory $path -Verbosity quiet
	   $dir = ls "$path\vswhere.*" | sort -property Name -descending | select -first 1
	   $file = ls -path "$dir" -name vswhere.exe -recurse
	   mv "$dir\$file" $vswhere   
	 }

	$MSBuild = &$vswhere -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | select-object -first 1
	if (-not (test-path $MSBuild)) {
	    throw "MSBuild not found!"
	}
}

Write-Host "MSBUILD = $MSBuild"


#trace
"Release path: $ReleaseFolder"

# Set the version number in SolutionInfo.cs
$SolutionInfoPath = Join-Path -Path $SolutionRoot -ChildPath "SolutionInfo.cs"
(gc -Path $SolutionInfoPath) `
	-replace "(?<=Version\(`")[.\d]*(?=`"\))", $ReleaseVersionNumber |
	sc -Path $SolutionInfoPath -Encoding UTF8;
(gc -Path $SolutionInfoPath) `
	-replace "(?<=AssemblyInformationalVersion\(`")[.\w-]*(?=`"\))", "$ReleaseVersionNumber$PreReleaseName" |
	sc -Path $SolutionInfoPath -Encoding UTF8;

# Set the copyright
$NowYear = (Get-Date).year
$Copyright = "Copyright " + $([char]0x00A9) + " Shannon Deminick $NowYear"

(gc -Path $SolutionInfoPath) `
	-replace "(?<=AssemblyCopyright\(`").*(?=`"\))", "$Copyright" |
	sc -Path $SolutionInfoPath -Encoding UTF8;

$SolutionPath = Join-Path -Path $SolutionRoot -ChildPath "UmbracoIdentity.sln";

#restore nuget packages
Write-Host "Restoring nuget packages..."
& $NuGet restore $SolutionPath

# clean sln for all deploys
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount /t:Clean
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

# Build the solution in release mode
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

$include = @('UmbracoIdentity.dll','UmbracoIdentity.pdb')
$CoreBinFolder = Join-Path -Path $SolutionRoot -ChildPath "UmbracoIdentity\bin\Release";
Copy-Item "$CoreBinFolder\*.*" -Destination $ReleaseFolder -Include $include

# COPY THE TRANSFORMS OVER
Copy-Item "$BuildFolder\web.config.install.xdt" -Destination (New-Item (Join-Path -Path $ReleaseFolder -ChildPath "nuget-transforms") -Type directory);

$AppStartFolder = Join-Path -Path $SolutionRoot -ChildPath "UmbracoIdentity.Web\App_Start";

# COPY THE CONTROLLERS OVER
$ControllerDestFolder = Join-Path -Path $ReleaseFolder -ChildPath "Controllers";
Copy-Item "$AppStartFolder\Controllers\*.cs" -Destination (New-Item ($ControllerDestFolder) -Type directory);

# COPY THE MODELS OVER
$ModelsDestFolder = Join-Path -Path $ReleaseFolder -ChildPath "Models";
Copy-Item "$AppStartFolder\Models" -Destination $ReleaseFolder -recurse -Container;

# COPY THE VIEWS OVER
$ViewsDestFolder = Join-Path -Path $ReleaseFolder -ChildPath "Views";
Copy-Item "$SolutionRoot\UmbracoIdentity.Web\Views\Account*.cshtml" -Destination (New-Item ($ViewsDestFolder) -Type directory);
Copy-Item "$SolutionRoot\UmbracoIdentity.Web\Views\UmbracoIdentityAccount\*.cshtml" -Destination (New-Item (Join-Path -Path $ViewsDestFolder -ChildPath "UmbracoIdentityAccount") -Type directory);

# COPY THE APP_STARTUP OVER
$AppStartDestFolder = Join-Path -Path $ReleaseFolder -ChildPath "App_Start";
Copy-Item "$AppStartFolder\UmbracoIdentityOwinStartup.cs" -Destination (New-Item ($AppStartDestFolder) -Type directory);

# COPY THE JS OVER
Copy-Item "$SolutionRoot\UmbracoIdentity.Web\Scripts\" -Destination $ReleaseFolder -recurse -Container -Filter *.js;

# Remove the DEGUB code from the startup class since we don't want to ship that
# NOTE: We're using the .Net constructs to do this because I could not get this to work with the powershell regex even with the (?s) prefix switch
$regex = New-Object System.Text.RegularExpressions.Regex ('#if\sDEBUG\s.*#endif', [System.Text.RegularExpressions.RegexOptions]::Singleline)
Set-Content -Path "$AppStartDestFolder\UmbracoIdentityOwinStartup.cs" $regex.Replace(([System.IO.File]::ReadAllText("$AppStartDestFolder\UmbracoIdentityOwinStartup.cs")), "") -Encoding UTF8;

# Rename all .cs files to .cs.pp
Get-ChildItem $AppStartDestFolder, $ControllerDestFolder, $ModelsDestFolder -Recurse -Filter *.cs | Rename-Item -newname {  $_.name  -Replace '\.cs$','.cs.pp'  }
Get-ChildItem $ViewsDestFolder -Recurse -Filter *.cshtml | Rename-Item -newname {  $_.name  -Replace '\.cshtml$','.cshtml.pp'  }

# Replace the namespace with the token in each file
Get-ChildItem $AppStartDestFolder, $ControllerDestFolder, $ModelsDestFolder, $ViewsDestFolder -Recurse -Filter *.pp |
Foreach-Object {
	(Get-Content $_.FullName) `
	-replace " UmbracoIdentity\.Web", " `$rootnamespace`$" |
	Set-Content $_.FullName -Encoding UTF8;
}

# COPY THE README OVER
Copy-Item "$BuildFolder\Readme.txt" -Destination $ReleaseFolder

# COPY OVER THE CORE NUSPEC AND BUILD THE NUGET PACKAGE
$CopyrightYear = (Get-Date).year;

Copy-Item "$BuildFolder\UmbracoIdentity.Core.nuspec" -Destination $ReleaseFolder
$CoreNuSpec = Join-Path -Path $ReleaseFolder -ChildPath "UmbracoIdentity.Core.nuspec";
Write-Output "DEBUGGING: " $CoreNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName
& $NuGet pack $CoreNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName -Properties copyrightyear=$CopyrightYear

Copy-Item "$BuildFolder\UmbracoIdentity.nuspec" -Destination $ReleaseFolder
$NuSpec = Join-Path -Path $ReleaseFolder -ChildPath "UmbracoIdentity.nuspec";
Write-Output "DEBUGGING: " $NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName
& $NuGet pack $NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName -Properties copyrightyear=$CopyrightYear

""
"Build $ReleaseVersionNumber$PreReleaseName is done!"
