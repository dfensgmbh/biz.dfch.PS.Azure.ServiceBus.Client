<#
.SYNOPSIS
Installs the module into a path inside $ENV:PSModulePath.


.DESCRIPTION
Installs the module into a path inside $ENV:PSModulePath. 
Any existing module customisations are overwritten by the 
installation routine (such as <module>.xml).

.EXAMPLE
Installs the module into the default directory.

PS > .\Install.ps1

.EXAMPLE
Installs the module into the C:\PSModules directory.

PS > .\Install.ps1 -ModulePath C:\PSModules
#>
[CmdletBinding()]
PARAM
( 
	# Specifies the module name. Leave as is.
	[string] $ModuleName = 'biz.dfch.PS.Azure.ServiceBus.Client'
	,
	# Specifies the target base directory into which to install the module.
    [string] $ModulePath = (Join-Path $env:ProgramFiles WindowsPowerShell\Modules)
)

end
{
    $targetDirectory = Join-Path $ModulePath $ModuleName
    $scriptRoot      = Split-Path $MyInvocation.MyCommand.Path -Parent
    $sourceDirectory = Join-Path $scriptRoot Tools

    if ($PSVersionTable.PSVersion.Major -ge 5)
    {
        $manifestFile    = Join-Path $sourceDirectory ('{0}.psd1' -f $ModuleName)
        $manifest        = Test-ModuleManifest -Path $manifestFile -WarningAction Ignore -ErrorAction Stop
        $targetDirectory = Join-Path $targetDirectory $manifest.Version.ToString()
    }

    Update-Directory -Source $sourceDirectory -Destination $targetDirectory

    if ($PSVersionTable.PSVersion.Major -lt 4)
    {
        $ModulePaths = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split ';'
        if ($ModulePaths -notcontains $ModulePath)
        {
            Write-Verbose "Adding '$ModulePath' to PSModulePath."

            $ModulePaths = @(
                $ModulePath
                $ModulePaths
            )

            $newModulePath = $ModulePaths -join ';'

            [Environment]::SetEnvironmentVariable('PSModulePath', $newModulePath, 'Machine')
            $env:PSModulePath += ";$ModulePath"
        }
    }
}

begin
{
    function Update-Directory
    {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string] $Source,

            [Parameter(Mandatory = $true)]
            [string] $Destination
        )

        $Source = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Source)
        $Destination = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Destination)

        if (-not (Test-Path -LiteralPath $Destination))
        {
            $null = New-Item -Path $Destination -ItemType Directory -ErrorAction Stop
        }

        try
        {
            $sourceItem = Get-Item -LiteralPath $Source -ErrorAction Stop
            $destItem = Get-Item -LiteralPath $Destination -ErrorAction Stop

            if ($sourceItem -isnot [System.IO.DirectoryInfo] -or $destItem -isnot [System.IO.DirectoryInfo])
            {
                throw 'Not Directory Info'
            }
        }
        catch
        {
            throw 'Both Source and Destination must be directory paths.'
        }

        $sourceFiles = Get-ChildItem -Path $Source -Recurse |
                       Where-Object { -not $_.PSIsContainer }

        foreach ($sourceFile in $sourceFiles)
        {
            $relativePath = Get-RelativePath $sourceFile.FullName -RelativeTo $Source
            $targetPath = Join-Path $Destination $relativePath

            $sourceHash = Get-FileHash -Path $sourceFile.FullName
            $destHash = Get-FileHash -Path $targetPath

            if ($sourceHash -ne $destHash)
            {
                $targetParent = Split-Path $targetPath -Parent

                if (-not (Test-Path -Path $targetParent -PathType Container))
                {
                    $null = New-Item -Path $targetParent -ItemType Directory -ErrorAction Stop
                }

                Write-Verbose "Updating file $relativePath to new version."
                Copy-Item $sourceFile.FullName -Destination $targetPath -Force -ErrorAction Stop
            }
        }

        $targetFiles = Get-ChildItem -Path $Destination -Recurse |
                       Where-Object { -not $_.PSIsContainer }

        foreach ($targetFile in $targetFiles)
        {
            $relativePath = Get-RelativePath $targetFile.FullName -RelativeTo $Destination
            $sourcePath = Join-Path $Source $relativePath

            if (-not (Test-Path $sourcePath -PathType Leaf))
            {
                Write-Verbose "Removing unknown file $relativePath from module folder."
                Remove-Item -LiteralPath $targetFile.FullName -Force -ErrorAction Stop
            }
        }

    }

    function Get-RelativePath
    {
        param ( [string] $Path, [string] $RelativeTo )
        return $Path -replace "^$([regex]::Escape($RelativeTo))\\?"
    }

    function Get-FileHash
    {
        param ([string] $Path)

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
        {
            return $null
        }

        $item = Get-Item -LiteralPath $Path
        if ($item -isnot [System.IO.FileSystemInfo])
        {
            return $null
        }

        $stream = $null

        try
        {
            $sha = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
            $stream = $item.OpenRead()
            $bytes = $sha.ComputeHash($stream)
            return [convert]::ToBase64String($bytes)
        }
        finally
        {
            if ($null -ne $stream) { $stream.Close() }
            if ($null -ne $sha)    { $sha.Clear() }
        }
    }
}
