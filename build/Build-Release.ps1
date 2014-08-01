param (
	[Parameter(Mandatory=$true)]
	[ValidatePattern("^\d\.\d\.(?:\d\.\d$|\d$)")]
	[string]
	$ReleaseVersionNumber,
	[Parameter(Mandatory=$true)]
	[string]
	[AllowEmptyString()]
	$PreReleaseName
)

$PSScriptFilePath = (Get-Item $MyInvocation.MyCommand.Path);
$RepoRoot = (get-item $PSScriptFilePath).Directory.Parent.FullName;
$SolutionRoot = Join-Path -Path $RepoRoot "src";

#trace
"Solution Root: $SolutionRoot"

$MSBuild = "$Env:SYSTEMROOT\Microsoft.NET\Framework\v4.0.30319\msbuild.exe";

# Make sure we don't have a release folder for this version already
$BuildFolder = Join-Path -Path $RepoRoot -ChildPath "build";
$ReleaseFolder = Join-Path -Path $BuildFolder -ChildPath "Releases\v$ReleaseVersionNumber$PreReleaseName";
if ((Get-Item $ReleaseFolder -ErrorAction SilentlyContinue) -ne $null)
{
	Write-Warning "$ReleaseFolder already exists on your local machine. It will now be deleted."
	Remove-Item $ReleaseFolder -Recurse
}
New-Item $ReleaseFolder -Type directory

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
$Copyright = "Copyright � Shannon Deminick ".(Get-Date).year
(gc -Path $SolutionInfoPath) `
	-replace "(?<=AssemblyCopyright\(`")[.\w-]*(?=`"\))", $Copyright |
	sc -Path $SolutionInfoPath -Encoding UTF8;

# Build the solution in release mode
$SolutionPath = Join-Path -Path $SolutionRoot -ChildPath "UmbracoIdentity.sln";

# clean sln for all deploys
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount /t:Clean
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

#build
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

$include = @('UmbracoIdentity.dll','UmbracoIdentity.pdb')
$CoreBinFolder = Join-Path -Path $SolutionRoot -ChildPath "UmbracoIdentity\bin\Release";
Copy-Item "$CoreBinFolder\*.*" -Destination $ReleaseFolder -Include $include

# COPY THE TRANSFORMS OVER
Copy-Item "$BuildFolder\nuget-transforms\web.config.install.xdt" -Destination (New-Item (Join-Path -Path $ReleaseFolder -ChildPath "nuget-transforms") -Type directory);
Copy-Item "$BuildFolder\nuget-transforms\web.config.uninstall.xdt" -Destination (Join-Path -Path $ReleaseFolder -ChildPath "nuget-transforms");

$AppCodeFolder = Join-Path -Path $SolutionRoot -ChildPath "UmbracoIdentity.Web\App_Code";

# COPY THE CONTROLLERS OVER
$ControllersFolder = Join-Path -Path $AppCodeFolder -ChildPath "Controllers";
$ControllerDestFolder = Join-Path -Path $ReleaseFolder -ChildPath "Controllers";
Copy-Item "$ControllersFolder\*.cs" -Destination (New-Item ($ControllerDestFolder) -Type directory);

# COPY THE MODELS OVER
$ModelsFolder = Join-Path -Path $AppCodeFolder -ChildPath "Models";
$ModelsDestFolder = Join-Path -Path $ReleaseFolder -ChildPath "Models";
Copy-Item $ModelsFolder -Destination $ReleaseFolder -recurse -Container;

# COPY THE APP_STARTUP OVER
$AppCodeDestFolder = Join-Path -Path $ReleaseFolder -ChildPath "App_Startup";
Copy-Item "$AppCodeFolder\UmbracoIdentityStartup.cs" -Destination (New-Item ($AppCodeDestFolder) -Type directory);

# Rename all .cs files to .cs.pp
Get-ChildItem $AppCodeDestFolder, $ControllerDestFolder, $ModelsDestFolder -Recurse -Filter *.cs | Rename-Item -newname {  $_.name  -Replace '\.cs$','.cs.pp'  }

# Replace the namespace with the token in each file
Get-ChildItem $AppCodeDestFolder, $ControllerDestFolder, $ModelsDestFolder -Recurse -Filter *.pp |
Foreach-Object {
	(Get-Content $_.FullName) `
	-replace " UmbracoIdentity\.Web", " `$rootnamespace`$" |
	Set-Content $_.FullName -Encoding UTF8;
}

# COPY OVER THE CORE NUSPEC AND BUILD THE NUGET PACKAGE
$CoreNuSpecSource = Join-Path -Path $BuildFolder -ChildPath "UmbracoIdentity.nuspec";
Copy-Item $CoreNuSpecSource -Destination $ReleaseFolder
$CoreNuSpec = Join-Path -Path $ReleaseFolder -ChildPath "UmbracoIdentity.nuspec";
$NuGet = Join-Path $SolutionRoot -ChildPath ".nuget\NuGet.exe"
Write-Output "DEBUGGING: " $CoreNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName
& $NuGet pack $CoreNuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber$PreReleaseName

""
"Build $ReleaseVersionNumber$PreReleaseName is done!"
"NuGet packages also created, so if you want to push them just run:"
"  nuget push $CoreNuSpec"