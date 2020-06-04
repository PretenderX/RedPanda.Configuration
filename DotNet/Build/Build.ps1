[CmdletBinding()]
param (
	[Alias('target')]
    [string]$BuildTarget,

	[ValidateSet('', 'Any CPU','x86','x64')]
	[Alias('p')]
	[string]$Platform,

	[ValidateSet('','Debug','Release')]
	[Alias('c')]
    [string]$Configuration,
	
	[Alias('output')]
    [string]$OutputFolder,
	
	[string]$NugetVersion,
	[switch]$SkipDownloadNuget,
	
	[string]$NugetPath,
	
	[Alias('config')]
	[string]$NugetConfigFile,
	
	[Alias('feeds')]
	[string[]]$NugetFeeds=@(),
	
	[Alias('user')]
	[string]$NugetUser,
	
	[Alias('pass')]
	[string]$NugetPassword,
	[switch]$StorePasswordInClearText,
	
	[switch]$ZipOutput,
	[string]$ZipOutputFileName
)

if($BuildTarget -eq '')
{
	$foundBuildFiles = Get-ChildItem -Include *.sln,*.csproj -Recurse -Name -Force -Depth 1 | select -index 0
	
	if($foundBuildFiles.count -eq 0)
	{
		write-host '未发现解决方案或项目文件, 请通过 -BuildTarget 参数指定.'
		
		return
	}
	
	if($foundBuildFiles.count -gt 0)
	{
		$BuildTarget = Resolve-Path ('./{0}' -f $foundBuildFiles | select -index 0)
		
		write-host ('发现编译目标:{0}' -f $BuildTarget)
	}
}

if($Platform -eq '')
{
	$Platform = 'Any CPU'
	
	write-host ('未指定处理器架构, 默认使用{0}, 可通过 -Platform 参数指定.' -f $Platform)
}

if($Configuration -eq '')
{
	$Configuration = 'Debug'
	
	write-host ('未指定编译配置, 默认使用到{0}, 可通过 -Configuration 参数指定.' -f $Configuration)
}

if($NugetPath -eq '')
{
	$NugetPath = './nuget.exe'
}

$needDownloadNuget = !(Test-Path -Path $NugetPath)

if($needDownloadNuget)
{
	if(!$SkipDownloadNuget.IsPresent)
	{
		write-host '即将下载nuget.exe, 可通过 -SkipDownloadNuget 参数跳过此步骤.'

		if($NugetVersion -eq '')
		{
			$NugetVersion = 'latest'
			write-host '即将下载最新的nuget.exe, 可通过 -NugetVersion 参数指定.'
		}
		else
		{
			$NugetVersion = 'v{0}' -f $NugetVersion
			write-host ('即将下载{0}版本的nuget.exe.' -f $NugetVersion)
		}

		$NugetDownloadUrl = 'https://dist.nuget.org/win-x86-commandline/{0}/nuget.exe' -f $NugetVersion

		Invoke-WebRequest -Uri $NugetDownloadUrl -OutFile $NugetPath
	}
	
	if (!(Test-Path -Path $NugetPath))
	{
		$NugetPath = 'nuget'
	}
}

if($NugetFeeds.count -gt 0 -and $NugetUser -ne '' -and $NugetPassword -ne '')
{
	if ($NugetConfigFile -eq '')
	{
		$configFileName = 'nuget.config'
		$foundNugetConfigFiles = Get-ChildItem -Include $configFileName -Recurse -Name -Force -Depth 2
		
		if($foundNugetConfigFiles.count -eq 0)
		{
			write-host ('未发现 {0} 文件, 请通过 -NugetConfigFile 参数指定.' -f $configFileName)
			
			break
		}
		
		$NugetConfigFile = Resolve-Path ('./{0}' -f $foundNugetConfigFiles | select -index 0)
		
		write-host ('发现nuget配置文件：{0}, 即将写入认证信息...' -f $NugetConfigFile)
	}

	foreach ($feed in $NugetFeeds)
	{
	
		$updateNugetConfigExpression = '{0} sources Update -ConfigFile {1} -Name {2} -Username {3} -Password {4}' -f $NugetPath,$NugetConfigFile,$feed,$NugetUser,$NugetPassword
	
		if ($StorePasswordInClearText.IsPresent)
		{
			$updateNugetConfigExpression = '{0} -StorePasswordInClearText' -f $updateNugetConfigExpression
		}
		
		Invoke-Expression $updateNugetConfigExpression
	}
}

if($OutputFolder -eq '')
{
	$OutputFolder = './build'
}

if (!(Test-Path -Path $OutputFolder)) {
	New-Item -Path $OutputFolder -ItemType 'Directory'
}

$OutputFolder = Resolve-Path -Path $OutputFolder

Remove-Item -Path $OutputFolder\* -Recurse -Force

write-host ('未指定输出目录, 默认输出到{0}, 可通过 -OutputFolder 参数指定.' -f $OutputFolder)

Invoke-Expression ('{0} restore "{1}" -Verbosity Detailed -NonInteractive' -f $NugetPath,$BuildTarget)

msbuild $BuildTarget /m /nologo /nr:false /p:DeployOnBuild=true /p:WebPublishMethod=Package /p:PackageAsSingleFile=true /p:SkipInvalidConfigurations=true /p:PackageLocation="$OutputFolder" /p:platform=$Platform /p:configuration=$Configuration

if($ZipOutput.IsPresent -or $ZipOutputFileName -ne '')
{
	if($ZipOutputFileName -eq '')
	{
		$ZipOutputFileName = './{0}.zip' -f (Get-Item $BuildTarget | Select-Object -ExpandProperty BaseName)
	}
	
	Compress-Archive -Path $OutputFolder/* -DestinationPath $ZipOutputFileName -Force
	
	write-host ('压缩包路径: {0}' -f (Resolve-Path $ZipOutputFileName))
}