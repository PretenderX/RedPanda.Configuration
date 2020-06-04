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
		write-host 'δ���ֽ����������Ŀ�ļ�, ��ͨ�� -BuildTarget ����ָ��.'
		
		return
	}
	
	if($foundBuildFiles.count -gt 0)
	{
		$BuildTarget = Resolve-Path ('./{0}' -f $foundBuildFiles | select -index 0)
		
		write-host ('���ֱ���Ŀ��:{0}' -f $BuildTarget)
	}
}

if($Platform -eq '')
{
	$Platform = 'Any CPU'
	
	write-host ('δָ���������ܹ�, Ĭ��ʹ��{0}, ��ͨ�� -Platform ����ָ��.' -f $Platform)
}

if($Configuration -eq '')
{
	$Configuration = 'Debug'
	
	write-host ('δָ����������, Ĭ��ʹ�õ�{0}, ��ͨ�� -Configuration ����ָ��.' -f $Configuration)
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
		write-host '��������nuget.exe, ��ͨ�� -SkipDownloadNuget ���������˲���.'

		if($NugetVersion -eq '')
		{
			$NugetVersion = 'latest'
			write-host '�����������µ�nuget.exe, ��ͨ�� -NugetVersion ����ָ��.'
		}
		else
		{
			$NugetVersion = 'v{0}' -f $NugetVersion
			write-host ('��������{0}�汾��nuget.exe.' -f $NugetVersion)
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
			write-host ('δ���� {0} �ļ�, ��ͨ�� -NugetConfigFile ����ָ��.' -f $configFileName)
			
			break
		}
		
		$NugetConfigFile = Resolve-Path ('./{0}' -f $foundNugetConfigFiles | select -index 0)
		
		write-host ('����nuget�����ļ���{0}, ����д����֤��Ϣ...' -f $NugetConfigFile)
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

write-host ('δָ�����Ŀ¼, Ĭ�������{0}, ��ͨ�� -OutputFolder ����ָ��.' -f $OutputFolder)

Invoke-Expression ('{0} restore "{1}" -Verbosity Detailed -NonInteractive' -f $NugetPath,$BuildTarget)

msbuild $BuildTarget /m /nologo /nr:false /p:DeployOnBuild=true /p:WebPublishMethod=Package /p:PackageAsSingleFile=true /p:SkipInvalidConfigurations=true /p:PackageLocation="$OutputFolder" /p:platform=$Platform /p:configuration=$Configuration

if($ZipOutput.IsPresent -or $ZipOutputFileName -ne '')
{
	if($ZipOutputFileName -eq '')
	{
		$ZipOutputFileName = './{0}.zip' -f (Get-Item $BuildTarget | Select-Object -ExpandProperty BaseName)
	}
	
	Compress-Archive -Path $OutputFolder/* -DestinationPath $ZipOutputFileName -Force
	
	write-host ('ѹ����·��: {0}' -f (Resolve-Path $ZipOutputFileName))
}