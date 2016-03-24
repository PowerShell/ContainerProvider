#region Variables
$script:location_modules = "$env:LOCALAPPDATA\ContainerImage"
$script:file_modules = "$script:location_modules\sources.txt"
$script:ContainerSources = $null
$script:wildcardOptions = [System.Management.Automation.WildcardOptions]::CultureInvariant -bor `
                          [System.Management.Automation.WildcardOptions]::IgnoreCase
$script:ContainerImageSearchIndex = "ContainerImageSearchIndex.txt"
$script:PSArtifactTypeModule = 'Module'
$script:PSArtifactTypeScript = 'Script'
$script:isNanoServerInitialized = $false
$script:isNanoServer = $false
$script:Providername = "ContainerImage"
$separator = "|#|"

Microsoft.PowerShell.Core\Set-StrictMode -Version Latest

#endregion Variables

#region One-Get Functions

function Find-Package
{ 
    [CmdletBinding()]
    param
    (
        [string[]]
        $names,

        [string]
        $RequiredVersion,

        [string]
        $MinimumVersion,

        [string]
        $MaximumVersion
    )

    Set-ModuleSourcesVariable

    $options = $request.Options

    foreach( $o in $options.Keys )
    {
        Write-Debug ( "OPTION: {0} => {1}" -f ($o, $options[$o]) )
    }

    $AllVersions = $null
    if($options.ContainsKey("AllVersions"))
    {
        $AllVersions = $options['AllVersions']
    }

    $sources = @()
    if($options.ContainsKey('Source'))
    {
        $sources = $options['Source']
    }

    $convertedRequiredVersion = Convert-Version $requiredVersion
    $convertedMinVersion = Convert-Version $minimumVersion
    $convertedMaxVersion = Convert-Version $maximumVersion

    if(-not (CheckVersion $convertedMinVersion $convertedMaxVersion $convertedRequiredVersion $AllVersions))
    {
        return $null
    }

    if ($null -eq $names -or $names.Count -eq 0)
    {
        $names = @('')
    }

    $allResults = @()
    $allSources = Get-Sources $sources
    foreach($currSource in $allSources)
    {
        foreach ($singleName in $names)
        {
            if ([string]::IsNullOrWhiteSpace($singleName) -or $singleName.Trim() -eq '*')
            {
                # if no name is supplied but min or max version is supplied, error out
                if ($null -ne $convertedMinVersion -or $null -ne $convertedMaxVersion)
                {
                    ThrowError -CallerPSCmdlet $PSCmdlet `
                                -ExceptionName System.Exception `
                                -ExceptionMessage "Name is required when either MinimumVersion or MaximumVersion parameter is used" `
                                -ExceptionObject $singleName `
                                -ErrorId NameRequiredForMinOrMaxVersion `
                                -ErrorCategory InvalidData
                }
            }

            $location = $currSource.SourceLocation
            $sourceName = $currSource.Name

            if($location.StartsWith("http://") -or $location.StartsWith("https://"))
            {
                $allResults += Find-Azure -Name $singleName `
                                    -MinimumVersion $convertedMinVersion `
                                    -MaximumVersion $convertedMaxVersion `
                                    -RequiredVersion $convertedRequiredVersion `
                                    -AllVersions:$AllVersions `
                                    -Location $location `
                                    -SourceName $sourceName
            }
            elseif($location.StartsWith("\\"))
            {
                $allResults += Find-UNCPath -Name $singleName `
                                    -MinimumVersion $convertedMinVersion `
                                    -MaximumVersion $convertedMaxVersion `
                                    -RequiredVersion $convertedRequiredVersion `
                                    -AllVersions:$AllVersions `
                                    -localPath $location `
                                    -SourceName $sourceName
            }
            else
            {
                Write-Error "Bad source '$sourceName' with location at $location"
            }
        }
    }

    if($null -eq $allResults)
    {
        return
    }

    foreach($result in $allResults)
    {
        $swid = New-SoftwareIdentityFromContainerImageItemInfo $result
        Write-Output $swid
    }
}

function Download-Package
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FastPackageReference,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Location
    )
    
    DownloadPackageHelper -FastPackageReference $FastPackageReference `
                            -Request $Request `
                            -Location $Location
}

function Install-Package
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FastPackageReference
    )

    [string[]] $splitterArray = @("$separator")    
    [string[]] $resultArray = $FastPackageReference.Split($splitterArray, [System.StringSplitOptions]::None)
    
    $name = $resultArray[0]
    $version = $resultArray[1]
    $Location = $script:location_modules

    $Destination = GenerateFullPath -Location $Location `
                                    -Name $name `
                                    -Version $Version

    $downloadOutput = DownloadPackageHelper -FastPackageReference $FastPackageReference `
                            -Request $Request `
                            -Location $Location
    
    $startInstallTime = Get-Date

    Write-Verbose "Trying to install the Image: $Destination"

    Install-ContainerOSImage -WimPath $Destination `
                             -Force

    $endInstallTime = Get-Date
    $differenceInstallTime = New-TimeSpan -Start $startInstallTime -End $endInstallTime
    $installTime = "Installed in " + $differenceInstallTime.Hours + " hours, " + $differenceInstallTime.Minutes + " minutes, " + $differenceInstallTime.Seconds + " seconds."
    Write-Verbose $installTime

    # Clean up
    Write-Verbose "Removing the installer: $Destination"
    rm $Destination
    
    Write-Output $downloadOutput
}

function Get-InstalledPackage
{
}

function Initialize-Provider
{
    write-debug "In $($script:Providername) - Initialize-Provider"
}

function Get-PackageProviderName
{
    return $script:Providername
}

#endregion One-Get Functions

#region Stand-Alone Functions

function Find-ContainerImage
{
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$false,Position=0)]
        [string[]]
        $Name,

        [System.Version]
        $MinimumVersion,

        [System.Version]
        $MaximumVersion,
        
        [System.Version]
        $RequiredVersion,

        [switch]
        $AllVersions,

        [System.string]
        $source
    )

    Begin
    {
    }

    Process
    {
        $PSBoundParameters["Provider"] = $script:Providername

        PackageManagement\Find-Package @PSBoundParameters
    }
}

function Save-ContainerImage
{
    [CmdletBinding(DefaultParameterSetName='NameAndPathParameterSet',
                   SupportsShouldProcess=$true)]
    Param
    (
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true,
                   Position=0,
                   ParameterSetName='NameAndPathParameterSet')]
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true,
                   Position=0,
                   ParameterSetName='NameAndLiteralPathParameterSet')]
        [ValidateNotNullOrEmpty()]

        [string[]]
        $Name,
        
        [Parameter(Mandatory=$true, 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='InputOjectAndPathParameterSet')]
        [Parameter(Mandatory=$true, 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='InputOjectAndLiteralPathParameterSet')]
        [ValidateNotNull()]
        [PSCustomObject[]]
        $InputObject,
        
        [Parameter(ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='NameAndPathParameterSet')]
        [Parameter(ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='NameAndLiteralPathParameterSet')]
        [Version]
        $MinimumVersion,

        [Parameter(ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='NameAndPathParameterSet')]
        [Parameter(ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='NameAndLiteralPathParameterSet')]
        [Version]
        $MaximumVersion,
        
        [Parameter(ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='NameAndPathParameterSet')]
        [Parameter(ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='NameAndLiteralPathParameterSet')]
        [Alias('Version')]
        [Version]
        $RequiredVersion,

        [Parameter(Mandatory=$true, ParameterSetName='NameAndPathParameterSet')]
        [Parameter(Mandatory=$true, ParameterSetName='InputOjectAndPathParameterSet')]
        [string]
        $Path,

        [Parameter(Mandatory=$true, ParameterSetName='NameAndLiteralPathParameterSet')]
        [Parameter(Mandatory=$true, ParameterSetName='InputOjectAndLiteralPathParameterSet')]
        [string]
        $LiteralPath,

        [Parameter()]
        [switch]
        $Force,

        [Parameter()]
        [System.string]
        $source
    )

    if($InputObject)
    {
    }
    else
    {
        $PSBoundParameters["Provider"] = $script:Providername
    }

    PackageManagement\Save-Package @PSBoundParameters
}

function Install-ContainerImage
{
    [CmdletBinding(DefaultParameterSetName='NameAndPathParameterSet',
                   SupportsShouldProcess=$true)]
    Param
    (
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true,
                   Position=0,
                   ParameterSetName='NameParameterSet')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Name,

        [Parameter(Mandatory=$true, 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0,
                   ParameterSetName='InputObject')]
        [ValidateNotNull()]
        [PSCustomObject[]]
        $InputObject,

        [Parameter(ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='NameParameterSet')]
        [Alias("Version")]
        [ValidateNotNull()]
        [Version]
        $MinimumVersion,

        [Parameter(ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='NameParameterSet')]
        [ValidateNotNull()]
        [Version]
        $MaximumVersion,

        [Parameter(ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='NameParameterSet')]
        [ValidateNotNull()]
        [Version]
        $RequiredVersion,

        [Parameter()]
        [switch]
        $Force,

        [Parameter()]
        [System.string]
        $Source
    )

    if($WhatIfPreference)
    {
        $null = $PSBoundParameters.Remove("WhatIf")
        $findOutput = PackageManagement\Find-Package @PSBoundParameters
        $packageName = $findOutput.name
        $packageversion = $findOutput.version
        $packageSource = $findOutput.Source

        $string = '"Package ' + $packageName + ' version ' + $packageversion + ' from ' + $packageSource + '"'
        $messageWhatIf = 'What if: Performing the operation "Install Package" on target ' + $string + ' .'

        Write-Host $messageWhatIf
        return
    }

    if($InputObject)
    {
    }
    else
    {
        $PSBoundParameters["Provider"] = $script:Providername
    }

    #PackageManagement\Install-Package @PSBoundParameters

    $Location = $script:location_modules

    $PSBoundParameters["Path"] = $Location
    $PSBoundParameters["Force"] = $true

    $downloadOutput = PackageManagement\Save-Package @PSBoundParameters
    
    $Destination = GenerateFullPath -Location $Location `
                                    -Name $downloadOutput.Name `
                                    -Version $downloadOutput.Version

    $startInstallTime = Get-Date

    Write-Verbose "Trying to install the Image: $Destination"

    Install-ContainerOSImage -WimPath $Destination `
                             -Force

    $endInstallTime = Get-Date
    $differenceInstallTime = New-TimeSpan -Start $startInstallTime -End $endInstallTime
    $installTime = "Installed in " + $differenceInstallTime.Hours + " hours, " + $differenceInstallTime.Minutes + " minutes, " + $differenceInstallTime.Seconds + " seconds."
    Write-Verbose $installTime

    # Clean up
    Write-Verbose "Removing the installer: $Destination"
    rm $Destination
}

#endregion Stand-Alone Functions

#region Helper-Functions

function CheckVersion
{
    param
    (
        [System.Version]$MinimumVersion,
        [System.Version]$MaximumVersion,
        [System.Version]$RequiredVersion,
        [switch]$AllVersions
    )

    if($AllVersions -and $RequiredVersion)
    {
        Write-Error "AllVersions and RequiredVersion cannot be used together"
        return $false
    }

    if($AllVersions -or $RequiredVersion)
    {
        if($MinimumVersion -or $MaximumVersion)
        {
            Write-Error "AllVersions and RequiredVersion switch cannot be used with MinimumVersion or MaximumVersion"
            return $false
        }
    }

    if($MinimumVersion -and $MaximumVersion)
    {
        if($MaximumVersion -lt $MinimumVersion)
        {
            Write-Error "Minimum Version cannot be more than Maximum Version"
            return $false
        }
    }

    return $true
}

function Find-Azure
{
    param(
        [Parameter(Mandatory=$false,Position=0)]
        [string[]]
        $Name,

        [System.Version]
        $MinimumVersion,

        [System.Version]
        $MaximumVersion,
        
        [System.Version]
        $RequiredVersion,

        [switch]
        $AllVersions,

        [System.String]
        $Location,

        [System.String]
        $SourceName
    )

    if(-not (IsNanoServer))
    {
        Add-Type -AssemblyName System.Net.Http
    }

    $searchFile = Get-SearchIndex -fwdLink $Location `
                                    -SourceName $SourceName
 
    $searchFileContent = Get-Content $searchFile

    if($null -eq $searchFileContent)
    {
        return $null
    }

    if(IsNanoServer)
    {
        $jsonDll = [Microsoft.PowerShell.CoreCLR.AssemblyExtensions]::LoadFrom($PSScriptRoot + "\Json.coreclr.dll")
        $jsonParser = $jsonDll.GetTypes() | Where-Object name -match jsonparser
        $searchContent = $jsonParser::FromJson($searchFileContent)
        $searchStuff = $searchContent.Get_Item("array0")
        $searchData = @()
        foreach($searchStuffEntry in $searchStuff)
        {
            $obj = New-Object PSObject 
            $obj | Add-Member NoteProperty Name $searchStuffEntry.Name
            $obj | Add-Member NoteProperty Version $searchStuffEntry.Version
            $obj | Add-Member NoteProperty Description $searchStuffEntry.Description
            $obj | Add-Member NoteProperty SasToken $searchStuffEntry.SasToken
            $searchData += $obj
        }
    }
    else
    {
        $searchData = $searchFileContent | ConvertFrom-Json
    }

    # If name is null or whitespace, interpret as *
    if ([string]::IsNullOrWhiteSpace($Name))
    {
        $Name = "*"
    }

    # Handle the version not given scenario
    if((-not ($MinimumVersion -or $MaximumVersion -or $RequiredVersion -or $AllVersions)))
    {
        $MinimumVersion = [System.Version]'0.0.0.0'
    }

    $searchResults = @()
    $searchDictionary = @{}

    foreach($entry in $searchData)
    {
        $toggle = $false

        # Check if the search string has * in it
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Name))
        {
            if($entry.name -like $Name)
            {
                $toggle = $true
            }
            else
            {
                continue
            }
        }
        else
        {
            if($entry.name -eq $Name)
            {
                $toggle = $true
            }
            else
            {
                continue
            }
        }

        $thisVersion = Convert-Version $entry.version

        if($MinimumVersion)
        {
            $convertedMinimumVersion = Convert-Version $MinimumVersion

            if(($thisVersion -ge $convertedMinimumVersion))
            {
                if($searchDictionary.ContainsKey($entry.name))
                {
                    $objEntry = $searchDictionary[$entry.name]
                    $objVersion = Convert-Version $objEntry.Version

                    if($thisVersion -gt $objVersion)
                    {
                        $toggle = $true
                    }
                    else
                    {
                        $toggle = $false
                    }
                }
                else
                {
                    $toggle = $true
                }   
            }
            else
            {
                $toggle = $false
            }
        }

        if($MaximumVersion)
        {
            $convertedMaximumVersion = Convert-Version $MaximumVersion

            if(($thisVersion -le $convertedMaximumVersion))
            {
                if($searchDictionary.ContainsKey($entry.name))
                {
                    $objEntry = $searchDictionary[$entry.name]
                    $objVersion = Convert-Version $objEntry.Version

                    if($thisVersion -gt $objVersion)
                    {
                        $toggle = $true
                    }
                    else
                    {
                        $toggle = $false
                    }
                }
                else
                {
                    $toggle = $true
                }
            }
            else
            {
                $toggle = $false
            }
        }

        if($RequiredVersion)
        {
            $convertedRequiredVersion = Convert-Version $RequiredVersion

            if(($thisVersion -eq $convertedRequiredVersion))
            {
                $toggle = $true                
            }
            else
            {
                $toggle = $false
            }
        }

        if($AllVersions)
        {
            if($toggle)
            {
                $searchResults += $entry
            }
        }

        if($toggle)
        {
            if($searchDictionary.ContainsKey($entry.name))
            {
                $searchDictionary.Remove($entry.name)
            }
            
            $searchDictionary.Add($entry.name, $entry)
        }
    }

    if(-not $AllVersions)
    {
        $searchDictionary.Keys | ForEach-Object {
                $searchResults += $searchDictionary.Item($_)
            }
    }

    $searchEntries = @()

    foreach($searchEntry in $searchResults)
    {
        $EntryName = $searchEntry.Name
        $EntryVersion = $searchEntry.Version
        $EntryDescription = $searchEntry.Description
        $SasToken = $searchEntry.SasToken
        $ResultEntry = Microsoft.PowerShell.Utility\New-Object PSCustomObject -Property ([ordered]@{
		    Name = $EntryName
		    Version = $EntryVersion
		    Description = $EntryDescription
		    SasToken = $SasToken
            Source = $SourceName
        })
        
        $searchEntries += $ResultEntry
    }

    $searchEntries = $searchEntries | Sort-Object "Version" -Descending

    return $searchEntries
}

function Find-UNCPath
{
    param(
        [Parameter(Mandatory=$false,Position=0)]
        [string]
        $Name,

        [System.Version]
        $MinimumVersion,

        [System.Version]
        $MaximumVersion,
        
        [System.Version]
        $RequiredVersion,

        [switch]
        $AllVersions,

        [System.String]
        $localPath,

        [System.String]
        $SourceName
    )

    $responseArray = @()
    try
    {
        $nameToSearch = ""
        if(-not $Name)
        {
            $nameToSearch = "*.wim"
        }
        else
        {
            if(-not($name.ToLower().EndsWith(".wim")))
            {
                $name = $name + ".wim"
            }

            $nameToSearch = $Name
        }

        $images = @()
        $images = Get-ChildItem -Path $localPath `
                                    -ErrorAction SilentlyContinue `
                                    -Filter $nameToSearch `
                                    -Recurse `
                                    -File `
                                    -Depth 1 `
                                    -Force | % { $_.FullName }

        $searchResults = @()
        $searchDictionary = @{}

        # Handle the version not given scenario
        if((-not ($MinimumVersion -or $MaximumVersion -or $RequiredVersion -or $AllVersions)))
        {
            $MinimumVersion = [System.Version]'0.0.0.0'
        }

        foreach($image in $images)
        {
            # Since the Get-ChildItem has filtered images by name
            # All images are potentially candidates for result
            $toggle = $true
            $thisVersion = get-Version $image
            $fileName = Split-Path $image -Leaf

            if($MinimumVersion)
            {
                $convertedMinimumVersion = Convert-Version $MinimumVersion

                if(($thisVersion -ge $convertedMinimumVersion))
                {
                    if($searchDictionary.ContainsKey($fileName))
                    {
                        $objEntry = $searchDictionary[$fileName]
                        $objVersion = Convert-Version $objEntry.Version

                        if($thisVersion -gt $objVersion)
                        {
                            $toggle = $true
                        }
                        else
                        {
                            $toggle = $false
                        }
                    }
                    else
                    {
                        $toggle = $true
                    }   
                }
                else
                {
                    $toggle = $false
                }
            }

            if($MaximumVersion)
            {
                $convertedMaximumVersion = Convert-Version $MaximumVersion

                if(($thisVersion -le $convertedMaximumVersion))
                {
                    if($searchDictionary.ContainsKey($fileName))
                    {
                        $objEntry = $searchDictionary[$fileName]
                        $objVersion = Convert-Version $objEntry.Version

                        if($thisVersion -gt $objVersion)
                        {
                            $toggle = $true
                        }
                        else
                        {
                            $toggle = $false
                        }
                    }
                    else
                    {
                        $toggle = $true
                    }
                }
                else
                {
                    $toggle = $false
                }
            }

            if($RequiredVersion)
            {
                $convertedRequiredVersion = Convert-Version $RequiredVersion

                if(($thisVersion -eq $convertedRequiredVersion))
                {
                    $toggle = $true                
                }
                else
                {
                    $toggle = $false
                }
            }

            if($AllVersions)
            {
                if($toggle)
                {
                    $searchResults += $image
                }
            }

            if($toggle)
            {
                if($searchDictionary.ContainsKey($fileName))
                {
                    $searchDictionary.Remove($fileName)
                }
            
                $searchDictionary.Add($fileName, $image)
            }
        }

        if(-not $AllVersions)
        {
            $searchDictionary.Keys | ForEach-Object {
                    $searchResults += $searchDictionary.Item($_)
                }
        }

        $searchEntries = @()

        foreach($searchEntry in $searchResults)
        {
            $entryName = Split-Path $searchEntry -Leaf
            $entryVersion = get-Version $searchEntry
            $entryDesc = $entryName
            $path = $localPath
            $ResultEntry = Microsoft.PowerShell.Utility\New-Object PSCustomObject -Property ([ordered]@{
		        Name = $EntryName
		        Version = $EntryVersion
		        Description = $EntryDesc
		        SasToken = $path
                Source = $SourceName
            })

            $searchEntries += $ResultEntry
        }

        return $searchEntries
    }
    catch
    {
        Write-Error "Unable to access the sub-folders of $localPath"
        return
    }
}

function Convert-Version([string]$version)
{
    if ([string]::IsNullOrWhiteSpace($version))
    {
        return $null;
    }

    # not supporting semver here. let's try to normalize the versions
    if ($version.StartsWith("."))
    {
        # add leading zeros
        $version = "0" + $version
    }
        
    # let's see how many parts are we given with the version
    $parts = $version.Split(".").Count

    # add .0 dependending number of parts since we need 4 parts
    while ($parts -lt 4)
    {
        $version = $version + ".0"
        $parts += 1
    }

    [version]$convertedVersion = $null

    # try to convert
    if ([version]::TryParse($version, [ref]$convertedVersion))
    {
        return $convertedVersion
    }

    return $null;
}

function IsNanoServer
{
    if ($script:isNanoServerInitialized)
    {
        return $script:isNanoServer
    }
    else
    {
        $script:isNanoServerInitialized = $true
        $operatingSystem = Get-CimInstance -ClassName win32_operatingsystem
        $systemSKU = $operatingSystem.OperatingSystemSKU
        $script:isNanoServer = ($systemSKU -eq 109) -or ($systemSKU -eq 144) -or ($systemSKU -eq 143)
        return $script:isNanoServer
    }
}

function Resolve-FwdLink
{
    param
    (
        [parameter(Mandatory=$false)]
        [System.String]$Uri
    )
    
    if(-not (IsNanoServer))
    {
        Add-Type -AssemblyName System.Net.Http
    }
    $httpClient = New-Object System.Net.Http.HttpClient
    $response = $httpclient.GetAsync($Uri)
    $link = $response.Result.RequestMessage.RequestUri

    return $link
}

function Get-SearchIndex
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]
        $fwdLink,

        [Parameter(Mandatory=$true)]
        [string]
        $SourceName
    )
    
    $fullUrl = Resolve-FwdLink $fwdLink
    $fullUrl = $fullUrl.AbsoluteUri
    $searchIndex = $SourceName + "_" + $script:ContainerImageSearchIndex
    $destination = Join-Path $script:location_modules $searchIndex

    if(-not(Test-Path $script:location_modules))
    {
        md $script:location_modules
    }

    if(Test-Path $destination)
    {
        Remove-Item $destination
        DownloadFile -downloadURL $fullUrl `
                    -destination $destination
    }
    else
    {
        DownloadFile -downloadURL $fullUrl `
                    -destination $destination
    }
    
    return $destination
} 

function DownloadFile
{
    [CmdletBinding()]
    param($downloadURL, $destination)
    
    $startTime = Get-Date

    try
    {
        # Download the file
        Write-Verbose "Downloading $downloadUrl to $destination"
        if(IsNanoServer)
        {
            $saveItemPath = $PSScriptRoot + "\SaveHTTPItemUsingBITS.psm1"
            Import-Module "$saveItemPath"
            Save-HTTPItemUsingBitsTransfer -Uri $downloadURL `
                            -Destination $destination
            
        }
        else
        {
            Start-BitsTransfer -Source $downloadURL `
                            -Destination $destination
        }

        Write-Verbose "Finished downloading"
        $endTime = Get-Date
        $difference = New-TimeSpan -Start $startTime -End $endTime
        $downloadTime = "Downloaded in " + $difference.Hours + " hours, " + $difference.Minutes + " minutes, " + $difference.Seconds + " seconds."
        Write-Verbose $downloadTime
    }
    catch
    {
        ThrowError -CallerPSCmdlet $PSCmdlet `
                    -ExceptionName $_.Exception.GetType().FullName `
                    -ExceptionMessage $_.Exception.Message `
                    -ExceptionObject $downloadURL `
                    -ErrorId FailedToDownload `
                    -ErrorCategory InvalidOperation        
    }
}

function New-SoftwareIdentityFromContainerImageItemInfo
{
    [Cmdletbinding()]
    param(
        [PSCustomObject]
        $package
    )

    $fastPackageReference = $package.Name + 
                                $separator + $package.version + 
                                $separator + $package.Description + 
                                $separator + $package.Source + 
                                $separator + $package.SasToken

    $Name = [System.IO.Path]::GetFileNameWithoutExtension($package.Name)

    $params = @{
                    FastPackageReference = $fastPackageReference;
                    Name = $Name;
                    Version = $package.version.ToString();
                    versionScheme  = "MultiPartNumeric";
                    Source = $package.Source;
                    Summary = $package.Description;
                }
    New-SoftwareIdentity @params
}

function get-Version
{
    param($fullPath)

    # Throw error if the given File is folder or doesn't exist
    if((Get-Item $fullPath) -is [System.IO.DirectoryInfo])
    {
        Write-Error "Please enter a file name not a folder."
        throw "$fullPath is a folder not file"
    }

    $containerImageInfo = Get-WindowsImage -ImagePath $fullPath -Index 1
    $containerImageVersion = $containerImageInfo.Version

    return $containerImageVersion
}

# Utility to throw an errorrecord
function ThrowError
{
    param
    (        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCmdlet]
        $CallerPSCmdlet,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]        
        $ExceptionName,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ExceptionMessage,
        
        [System.Object]
        $ExceptionObject,
        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorCategory]
        $ErrorCategory
    )
        
    $exception = New-Object $ExceptionName $ExceptionMessage;
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $ErrorId, $ErrorCategory, $ExceptionObject    
    $CallerPSCmdlet.ThrowTerminatingError($errorRecord)
}

function DownloadPackageHelper
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FastPackageReference,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Location,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $request
    )

    [string[]] $splitterArray = @("$separator")
    
    [string[]] $resultArray = $fastPackageReference.Split($splitterArray, [System.StringSplitOptions]::None)

    $name = $resultArray[0]
    $version = $resultArray[1]
    $description = $resultArray[2]
    $source = $resultArray[3]
    $sasToken = $resultArray[4]

    if($sasToken.StartsWith("\\"))
    {
        $sasToken = Join-Path $sasToken $name
    }

    $options = $request.Options

    foreach( $o in $options.Keys )
    {
        Write-Debug ( "OPTION: {0} => {1}" -f ($o, $options[$o]) )
    }

    $Force = $false
    if($options.ContainsKey("Force"))
    {
        $Force = $options['Force']
    }

    if(-not (Test-Path $Location))
    {
        if($Force)
        {
            Write-Verbose "Creating: $Location as it doesn't exist."
            mkdir $Location
        }
        else
        {
            $errorMessage = ("Cannot find the path '{0}' because it does not exist" -f $Location)
            ThrowError  -ExceptionName "System.ArgumentException" `
                    -ExceptionMessage $errorMessage `
                    -ErrorId "PathNotFound" `
                    -CallerPSCmdlet $PSCmdlet `
                    -ExceptionObject $Location `
                    -ErrorCategory InvalidArgument
        }
    }

    $fullPath = GenerateFullPath -Location $Location `
                                    -Name $name `
                                    -Version $Version

    if(Test-Path $fullPath)
    {
        if($Force)
        {
            $existingFileItem = get-item $fullPath
            if($existingFileItem.isreadonly)
            {
                throw "Cannot remove read-only file $fullPath. Remove read-only and use -Force again."
            }
            else
            {
                Remove-Item $fullPath
                DownloadFile $sasToken $fullPath
            }
        }
        else
        {
            Write-Verbose "$fullPath already exists. Skipping save. Use -Force to overwrite."
        }
    }
    else
    {
        DownloadFile $sasToken $fullPath
    }

    $savedWindowsPackageItem = Microsoft.PowerShell.Utility\New-Object PSCustomObject -Property ([ordered]@{
		                Name = $name
		                Version = $version
		                Description = $description
		                SasToken = $sasToken
                        Source = $source
                        FullPath = $fullPath
                    })

    Write-Output (New-SoftwareIdentityFromContainerImageItemInfo $savedWindowsPackageItem)
}

function GenerateFullPath
{
    param
    (
        [Parameter(Mandatory=$true)]
        [System.String]
        $Location,

        [Parameter(Mandatory=$true)]
        [System.String]
        $Name,

        [Parameter(Mandatory=$true)]
        [System.Version]
        $Version
    )

    $fileName = $name + "-" + $Version.ToString().replace('.','-') + ".wim"
    $fullPath = Join-Path $Location $fileName

    return $fullPath
}

#endregion Helper-Functions

#region PackageSource Functions

function Get-Sources
{
    param($sources)

    Set-ModuleSourcesVariable

    $listOfSources = @()
    
    foreach($mySource in $script:ContainerSources.Values)
    {
        if((-not $sources) -or
            (($mySource.Name -eq $sources) -or
               ($mySource.SourceLocation -eq $sources)))
        {
            $tempHolder = @{}

            $location = $mySource."SourceLocation"
            $tempHolder.Add("SourceLocation", $location)
            
            $packageSourceName = $mySource.Name
            $tempHolder.Add("Name", $packageSourceName)
            
            $listOfSources += $tempHolder
        }
    }

    return $listOfSources
}

function DeSerialize-PSObject
{
    [CmdletBinding(PositionalBinding=$false)]    
    Param
    (
        [Parameter(Mandatory=$true)]        
        $Path
    )
    $filecontent = Microsoft.PowerShell.Management\Get-Content -Path $Path
    [System.Management.Automation.PSSerializer]::Deserialize($filecontent)    
}

function Set-ModuleSourcesVariable
{
    [CmdletBinding()]
    param([switch]$Force)

    if(Microsoft.PowerShell.Management\Test-Path $script:file_modules)
    {
        $script:ContainerSources = DeSerialize-PSObject -Path $script:file_modules
    }
    else
    {
        $script:ContainerSources = [ordered]@{}
                
        $defaultModuleSource = Microsoft.PowerShell.Utility\New-Object PSCustomObject -Property ([ordered]@{
            Name = "ContainerImageGallery"
            SourceLocation = "http://go.microsoft.com/fwlink/?LinkID=746630&clcid=0x409"
            Trusted=$false
            Registered= $true
            InstallationPolicy = "Untrusted"
        })

        $script:ContainerSources.Add("ContainerImageGallery", $defaultModuleSource)
        Save-ModuleSources
    }
}

function Save-ModuleSources
{
    # check if exists
    if(-not (Test-Path $script:location_modules))
    {
        $null = md $script:location_modules
    }

    # seralize module
    Microsoft.PowerShell.Utility\Out-File -FilePath $script:file_modules `
                                            -Force `
                                            -InputObject ([System.Management.Automation.PSSerializer]::Serialize($script:ContainerSources))
}

function Get-DynamicOptions
{
    param
    (
        [Microsoft.PackageManagement.MetaProvider.PowerShell.OptionCategory]
        $category
    )
}

function Add-PackageSource
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name,
         
        [string]
        $Location,

        [bool]
        $Trusted
    )

    Set-ModuleSourcesVariable -Force

    $Options = $request.Options

    # Add new module source
    $moduleSource = Microsoft.PowerShell.Utility\New-Object PSCustomObject -Property ([ordered]@{
            Name = $Name
            SourceLocation = $Location            
            Trusted=$Trusted
            Registered= $true
            InstallationPolicy = if($Trusted) {'Trusted'} else {'Untrusted'}
    })

    #TODO: Check if name already exists
    $script:ContainerSources.Add($Name, $moduleSource)

    Save-ModuleSources

    Write-Output -InputObject (New-PackageSourceFromModuleSource -ModuleSource $moduleSource)
}

function Remove-PackageSource
{
    param
    (
        [string]
        $Name
    )
    
    Set-ModuleSourcesVariable -Force

    if(-not $script:ContainerSources.Contains($Name))
    {
        Write-Error -Message "Package source $Name not found" `
                        -ErrorId "Package source $Name not found" `
                        -Category InvalidOperation `
                        -TargetObject $Name
        continue
    }

    $script:ContainerSources.Remove($Name)

    Save-ModuleSources

    #Write-Verbose ($LocalizedData.PackageSourceUnregistered -f ($Name))
}

function Resolve-PackageSource
{
    Set-ModuleSourcesVariable
    $SourceName = $request.PackageSources
    
    if(-not $SourceName)
    {
        $SourceName = "*"
    }

    foreach($moduleSourceName in $SourceName)
    {
        if($request.IsCanceled)
        {
            return
        }

        $wildcardPattern = New-Object System.Management.Automation.WildcardPattern $moduleSourceName,$script:wildcardOptions
        $moduleSourceFound = $false

        $script:ContainerSources.GetEnumerator() | 
            Microsoft.PowerShell.Core\Where-Object {$wildcardPattern.IsMatch($_.Key)} | 
                Microsoft.PowerShell.Core\ForEach-Object {

                    $moduleSource = $script:ContainerSources[$_.Key]

                    $packageSource = New-PackageSourceFromModuleSource -ModuleSource $moduleSource

                    Write-Output -InputObject $packageSource

                    $moduleSourceFound = $true
                }

        if(-not $moduleSourceFound)
        {
            $sourceName  = Get-SourceName -Location $moduleSourceName

            if($sourceName)
            {
                $moduleSource = $script:ContainerSources[$sourceName]

                $packageSource = New-PackageSourceFromModuleSource -ModuleSource $moduleSource

                Write-Output -InputObject $packageSource
            }
            
        }
    }
}

function New-PackageSourceFromModuleSource
{
    param
    (
        [Parameter(Mandatory=$true)]
        $ModuleSource
    )

    $packageSourceDetails = @{}

    # create a new package source
    $src =  New-PackageSource -Name $ModuleSource.Name `
                              -Location $ModuleSource.SourceLocation `
                              -Trusted $ModuleSource.Trusted `
                              -Registered $ModuleSource.Registered `
                              -Details $packageSourceDetails

    # return the package source object.
    Write-Output -InputObject $src
}

function Get-SourceName
{
    [CmdletBinding()]
    [OutputType("string")]
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Location
    )

    Set-ModuleSourcesVariable

    foreach($psModuleSource in $script:ContainerSources.Values)
    {
        if(($psModuleSource.Name -eq $Location) -or
           ($psModuleSource.SourceLocation -eq $Location))
        {
            return $psModuleSource.Name
        }
    }
}

#endregion PackageSource Functions

#region Export
Export-ModuleMember -Function Find-Package, `
                              Download-Package, `
                              Install-Package, `
                              #Uninstall-Package, `
                              Get-InstalledPackage, `
                              Add-PackageSource, `
                              Remove-PackageSource, `
                              Resolve-PackageSource, `
                              Get-DynamicOptions, `
                              Initialize-Provider, `
                              Get-PackageProviderName, `
                              Find-ContainerImage, `
                              Save-ContainerImage, `
                              Install-ContainerImage
#endregion Export