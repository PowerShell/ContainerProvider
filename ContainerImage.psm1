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

    if(-not (Test-Path $destination))
    {
        Write-verbose "$Destination does not exist"
    }
    else
    {
        Write-verbose "$Destination does exist. I should install"
    }

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
    <#
    .Synopsis
        Finds the container image from an online gallery that match specified criteria.
        It can also search from other registered sources.
    .DESCRIPTION
       Find-ContainerImage finds the images from the online gallery that match specified criteria.
    .EXAMPLE
       Find-ContainerImage -Name ImageName
    .EXAMPLE
       Find-ContainerImage -MinimumVersion Version
    .EXAMPLE
       Find-ContainerImage -MaximumVersion Version
    .EXAMPLE
       Find-ContainerImage -RequiredVersion Version
    .EXAMPLE
       Find-ContainerImage -AllVersions
    #>

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
    <#
    .Synopsis
        Saves a container image without installing it.
    .DESCRIPTION
       The Save-ContainerImage cmdlet lets you save a container image locally without installing it.
       This lets you inspect the container image  before you install, helping to minimize the risks
       of malicious code or malware on your system.
       As a best practice, when you have finished evaluating a container image for potential risks,
       and before you install the image for use, delete the image from the path to which you have saved.
    .EXAMPLE
       Save-ContainerImage -Name ImageName -Path C:\temp\
    .EXAMPLE
       Save-ContainerImage -Name ImageName -LiteralPath C:\temp\
    .EXAMPLE
       Save-ContainerImage -Name ImageName -MinimumVersion Version -Path .\..\
    .EXAMPLE
       Save-ContainerImage -Name ImageName -MaximumVersion Version -LiteralPath C:\temp\
    .EXAMPLE
       Save-ContainerImage -Name ImageName -RequiredVersion Version -Path C:\t*p\
    .EXAMPLE
       Save-ContainerImage -Name ImageName -RequiredVersion Version -Path C:\t*p\ -Source ContainerImageGallery    
    .EXAMPLE
        Find-ContainerImage -Name ImageName | Save-ContainerImage -LiteralPath C:\temp\
    #>

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
    <#
    .Synopsis
        Downloads the image from the cloud and installs them on the local computer.
    .DESCRIPTION
       The Install-ContainerImage gets the container image that meets the specified cirteria from the cloud.
        It saves the image locally and then installs it.
    .EXAMPLE
       Install-ContainerImage -Name ImageName
    .EXAMPLE
       Install-ContainerImage -Name ImageName -Source ContainerImageGallery
    .EXAMPLE
       Install-ContainerImage -Name ImageName -MinimumVersion Version
    .EXAMPLE
       Install-ContainerImage -Name ImageName -MaximumVersion Version
    .EXAMPLE
       Install-ContainerImage -Name ImageName -RequiredVersion Version
    .EXAMPLE
       Find-ContainerImage -Name ImageName | Install-ContainerImage
    #>

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
        $operatingSystem = Get-CimInstance -ClassName win32_operatingsystem
        $systemSKU = $operatingSystem.OperatingSystemSKU
        $script:isNanoServer = ($systemSKU -eq 109) -or ($systemSKU -eq 144) -or ($systemSKU -eq 143)
        $script:isNanoServerInitialized = $true
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

    try
    {
        # Download the file
        if($downloadURL.StartsWith("http://") -or $downloadURL.StartsWith("https://"))
        {
            if(-not (CheckDiskSpace $destination $downloadURL))
            {
                return
            }

            Write-Verbose "Downloading $downloadUrl to $destination"
            $saveItemPath = $PSScriptRoot + "\SaveHTTPItemUsingBITS.psm1"
            Import-Module "$saveItemPath"
            $startTime = Get-Date
            Save-HTTPItemUsingBitsTransfer -Uri $downloadURL `
                            -Destination $destination

            Write-Verbose "Finished downloading"
            $endTime = Get-Date
            $difference = New-TimeSpan -Start $startTime -End $endTime
            $downloadTime = "Downloaded in " + $difference.Hours + " hours, " + $difference.Minutes + " minutes, " + $difference.Seconds + " seconds."
            Write-Verbose $downloadTime
        }
        elseif($downloadURL.StartsWith("\\"))
        {
            $startTime = Get-Date
            cp $downloadURL $destination
            $endTime = Get-Date
            $difference = New-TimeSpan -Start $startTime -End $endTime
            $downloadTime = "Downloaded in " + $difference.Hours + " hours, " + $difference.Minutes + " minutes, " + $difference.Seconds + " seconds."
            Write-Verbose $downloadTime
        }
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

    $fileExtension = ".wim"

    if($Name.EndsWith($fileExtension))
    {
        $Name = $name.TrimEnd($fileExtension)
    }

    $fileName = $name + "-" + $Version.ToString().replace('.','-') + $fileExtension
    $fullPath = Join-Path $Location $fileName
    return $fullPath
}

function CheckDiskSpace
{
    param($Destination, $token)

    $headers = @{'x-ms-client-request-id'=$(hostname);'x-ms-version'='2015-02-21'}
    $httpresponse = Invoke-HttpClient -FullUri $token `
                                    -Headers $headers `
                                    -Method Head `
                                    -ea SilentlyContinue `
                                    -ev ev
    
    $contentLength = $httpresponse.Headers.ContentLength    
    $parent = Split-Path $Destination -Parent
    $Drive = (Get-Item $parent).PSDrive.Name
    $getDriveSpace = get-ciminstance win32_logicaldisk | Where-Object {$_.DeviceID -match $Drive} | % Freespace

    $contentLengthInMB = [math]::Round($contentLength/1mb, 2)
    $driveSpaceInIMB = [math]::Round($getDriveSpace/1mb, 2)

    Write-Verbose "Download size: $($contentLengthInMB)MB"
    Write-Verbose "Free space on the drive: $($driveSpaceInIMB)MB"

    if($contentLength -ge ($getDriveSpace * 0.95))
    {
        Write-Error "Not enough space to save the file"
        return $false
    }
    return $true
}

function Invoke-HTTPClient
{
   param(
      [Uri] $FullUri,
      [Hashtable] $Headers,
      [ValidateSet('Get','Head')]
      [string] $httpMethod,
      [int] $retryCount = 0
   )

   $poshExtensionExist = ([psobject].Assembly.GetType('Microsoft.PowerShell.CoreCLR.AssemblyExtensions'))
   if ($poshExtensionExist)
   {
        # Nano case
        $snhAssemblyPath = join-path $env:windir "System32\DotNetCore\v1.0\System.Net.Http.dll"
        $null = [Microsoft.PowerShell.CoreCLR.AssemblyExtensions]::LoadFrom($snhAssemblyPath )
   }
   else
   {
        # Non-Nano case
        Add-Type -AssemblyName System.Net.Http
   }

   do
   {
        $httpClient = [System.Net.Http.HttpClient]::new()
        foreach($headerKey in $Headers.Keys)
        {
            $httpClient.DefaultRequestHeaders.Add($headerKey, $Headers[$headerKey])
        }
  
        $HttpCompletionOption = 'ResponseContentRead'
        if ($httpMethod -eq 'Get')
        {   
            $httpRequestMessage = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $fullUri)
        }
        else
        {
            $httpRequestMessage = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head, $fullUri)
            $HttpCompletionOption = 'ResponseHeadersRead'
        }  
   
        $result = $httpClient.SendAsync($httpRequestMessage, $HttpCompletionOption)
        $null = $result.AsyncWaitHandle.WaitOne()

        if ($result.Result.IsSuccessStatusCode)
        {
            break;
        }
        $retryCount--;
        $msg = 'RetryCount: {0}, Http.GetAsync did not return successful status code. Status Code: {1}, {2}' -f `
                    $retryCount, $result.Result.StatusCode, $result.Result.ReasonPhrase 
        $msg = $msg + ('Result Reason Phrase: {0}' -f $result.Result.ReasonPhrase)
   } while($retryCount -gt 0)

   if (-not $result.Result.IsSuccessStatusCode)
   {
       $msg = 'Http.GetAsync did not return successful status code. Status Code: {0}, {1}' -f `
                    $result.Result.StatusCode, $result.Result.ReasonPhrase    
       throw $msg
   }
   return $result.Result.Content
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
# SIG # Begin signature block
# MIIargYJKoZIhvcNAQcCoIIanzCCGpsCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUIo+QjxS6NJsTO1spGPscGGVY
# EWWgghWBMIIEwjCCA6qgAwIBAgITMwAAAJJMoq9VJwgudQAAAAAAkjANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTUxMDA3MTgxNDE0
# WhcNMTcwMTA3MTgxNDE0WjCBsjELMAkGA1UEBhMCVVMxEjAQBgNVBAgTCVdhc2lu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046
# N0QyRS0zNzgyLUIwRjcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNl
# cnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC6WVT9G7wUxF8u
# /fnFTnid7MCYX4X58613PUnaf2uYaz291cpmbxNeEsx+HZ8xrgjCHkMC3U9rTUfl
# oyhWqlW3ZdZQdn97Qa++X7wXa/ybE8FeY0Qphe8K0w9hbhxRjbII4fInEEkM4GAd
# HLqPqQw+U+Ul/gAC8U64SnklxtsjxN2faP98po9YqDYGH/IGaej0Y9ojGA2aEpVh
# J6n3TezIbXNZDBZW1ODKX1W0OmKPNvTdGqFYAHCr6osCrVLyg4ROozoI9GnsvjC7
# f9ACbPJf6Xy1B2v0teYREkUmpqc+OC/rZpApjgtL2Y5ymgeuihuSUj/XaKNtDa0Z
# ERONWgyLAgMBAAGjggEJMIIBBTAdBgNVHQ4EFgQUBsPfWqqHee6gVxN8Wohmb0CT
# pgMwHwYDVR0jBBgwFoAUIzT42VJGcArtQPt2+7MrsMM1sw8wVAYDVR0fBE0wSzBJ
# oEegRYZDaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljcm9zb2Z0VGltZVN0YW1wUENBLmNybDBYBggrBgEFBQcBAQRMMEowSAYIKwYB
# BQUHMAKGPGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0VGltZVN0YW1wUENBLmNydDATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG
# 9w0BAQUFAAOCAQEAjgD2Z96da+Ze+YXIxGUX2pvvvX2etiR572Kwk6j6aXOFJrbB
# FaNelpipwJCRAY/V9qLIqUh+KfQFBKQYlRBf50WrCcXz+sx0BxyG597HjjGCmL4o
# Y0j/F0KATLMw60EcOh2I1hotO1a1W5fHB661OxD+T5KC6D9JN9TTP8vxap080i/V
# uNKyr2QubnfuOvs7jTjDJP5l5ZUEAFcxuliihARHhKnyoWxWcvje/fI463+pmRhF
# /nBuA3jTiCC5DWI3vST9I0l/BwrVDVMwvvnn5xf0vHb1U3TrJVeo2VRpHsqsoCA0
# 35Vuya6u01jEDkKhrZHuuMnxTAgCVuIFeXh9xDCCBOwwggPUoAMCAQICEzMAAAEK
# LHmu13l7pqwAAQAAAQowDQYJKoZIhvcNAQEFBQAweTELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEjMCEGA1UEAxMaTWljcm9zb2Z0IENvZGUgU2ln
# bmluZyBQQ0EwHhcNMTUwNjA0MTc0MjQ1WhcNMTYwOTA0MTc0MjQ1WjCBgzELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9QUjEe
# MBwGA1UEAxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAkvxvNrvhA7ko1kbRomG6pUb7YxY+LvlH0sfs7ceZsSZR
# db3azA8GFBGkbBmewF9NVInkTVDYjc2hYaV3E5ocp+0NdPenVnnoKPdT0rF6Y+D1
# lJe37NlH+Gw98yWIs7wKxQSnjnyFSHYcYUaqGcR6YovBwjWq+1hvxWMLk0kwgRt7
# 3398T7RHbV94HK+295YTUu+50U055XPeSE48FKqXDTnMi1HhXNE78I5n6jBgqU1a
# nUO92yO6wA/XSxCdnE3wUaKEquScpz3Wo+8KGEio+rFOpZgOS7/wFPMAyLBI1lv+
# ONeJES0FukMCTyIAliWtfTVuhGirIBg4KP4cohCxpQIDAQABo4IBYDCCAVwwEwYD
# VR0lBAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYEFIn+CjHqJs3mbceRkbmUjKIYYTc0
# MFEGA1UdEQRKMEikRjBEMQ0wCwYDVQQLEwRNT1BSMTMwMQYDVQQFEyozMTU5NSsw
# NDA3OTM1MC0xNmZhLTRjNjAtYjZiZi05ZDJiMWNkMDU5ODQwHwYDVR0jBBgwFoAU
# yxHoytK0FlgByTcuMxYWuUyaCh8wVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljQ29kU2lnUENBXzA4
# LTMxLTIwMTAuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNDb2RTaWdQQ0FfMDgtMzEt
# MjAxMC5jcnQwDQYJKoZIhvcNAQEFBQADggEBAKaoU5HfOwH+YV0GWutm8AzY99mE
# 0wBRDhDRpNEXKOeMMzgr2EPGA4t16zOS9KniZ/0C26UdTkNFXRtJ4+BPFvB+j/CI
# EcqCraT7pqlf9ZdgyHvEv3ybae0fgsHxzY54S2L11w0c11MS1pZS7zW9GY6gQJOh
# CqUtFpzCRnQI69v02KVJNlQSEVUDs3sW+0f++2j8wEVc4j8SeTOi74LF3kAZB+4V
# xQqbWQVBqdCXnoGeA1v8SuMaLgWsUEcvjPp52B4g+AX7KWsYFPpyBLcLp5pk7BFd
# T0VJjSkaLfvQtglTXzSU4BbEuepzNehX7+HrFsMYxwazO89hhOK2RImUo4YwggW8
# MIIDpKADAgECAgphMyYaAAAAAAAxMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJ
# k/IsZAEZFgNjb20xGTAXBgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMT
# JE1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0xMDA4MzEy
# MjE5MzJaFw0yMDA4MzEyMjI5MzJaMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENB
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsnJZXBkwZL8dmmAgIEKZ
# dlNsPhvWb8zL8epr/pcWEODfOnSDGrcvoDLs/97CQk4j1XIA2zVXConKriBJ9PBo
# rE1LjaW9eUtxm0cH2v0l3511iM+qc0R/14Hb873yNqTJXEXcr6094CholxqnpXJz
# VvEXlOT9NZRyoNZ2Xx53RYOFOBbQc1sFumdSjaWyaS/aGQv+knQp4nYvVN0UMFn4
# 0o1i/cvJX0YxULknE+RAMM9yKRAoIsc3Tj2gMj2QzaE4BoVcTlaCKCoFMrdL109j
# 59ItYvFFPeesCAD2RqGe0VuMJlPoeqpK8kbPNzw4nrR3XKUXno3LEY9WPMGsCV8D
# 0wIDAQABo4IBXjCCAVowDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUyxHoytK0
# FlgByTcuMxYWuUyaCh8wCwYDVR0PBAQDAgGGMBIGCSsGAQQBgjcVAQQFAgMBAAEw
# IwYJKwYBBAGCNxUCBBYEFP3RMU7TJoqV4ZhgO6gxb6Y8vNgtMBkGCSsGAQQBgjcU
# AgQMHgoAUwB1AGIAQwBBMB8GA1UdIwQYMBaAFA6sgmBAVieX5SUT/CrhClOVWeSk
# MFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
# Y3JsL3Byb2R1Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRI
# MEYwRAYIKwYBBQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljcm9zb2Z0Um9vdENlcnQuY3J0MA0GCSqGSIb3DQEBBQUAA4ICAQBZOT5/
# Jkav629AsTK1ausOL26oSffrX3XtTDst10OtC/7L6S0xoyPMfFCYgCFdrD0vTLqi
# qFac43C7uLT4ebVJcvc+6kF/yuEMF2nLpZwgLfoLUMRWzS3jStK8cOeoDaIDpVbg
# uIpLV/KVQpzx8+/u44YfNDy4VprwUyOFKqSCHJPilAcd8uJO+IyhyugTpZFOyBvS
# j3KVKnFtmxr4HPBT1mfMIv9cHc2ijL0nsnljVkSiUc356aNYVt2bAkVEL1/02q7U
# gjJu/KSVE+Traeepoiy+yCsQDmWOmdv1ovoSJgllOJTxeh9Ku9HhVujQeJYYXMk1
# Fl/dkx1Jji2+rTREHO4QFRoAXd01WyHOmMcJ7oUOjE9tDhNOPXwpSJxy0fNsysHs
# cKNXkld9lI2gG0gDWvfPo2cKdKU27S0vF8jmcjcS9G+xPGeC+VKyjTMWZR4Oit0Q
# 3mT0b85G1NMX6XnEBLTT+yzfH4qerAr7EydAreT54al/RrsHYEdlYEBOsELsTu2z
# dnnYCjQJbRyAMR/iDlTd5aH75UcQrWSY/1AWLny/BSF64pVBJ2nDk4+VyY3YmyGu
# DVyc8KKuhmiDDGotu3ZrAB2WrfIWe/YWgyS5iM9qqEcxL5rc43E91wB+YkfRzojJ
# uBj6DnKNwaM9rwJAav9pm5biEKgQtDdQCNbDPTCCBgcwggPvoAMCAQICCmEWaDQA
# AAAAABwwDQYJKoZIhvcNAQEFBQAwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5MB4XDTA3MDQwMzEyNTMwOVoXDTIxMDQwMzEz
# MDMwOVowdzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8G
# A1UEAxMYTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAn6Fssd/bSJIqfGsuGeG94uPFmVEjUK3O3RhOJA/u0afR
# TK10MCAR6wfVVJUVSZQbQpKumFwwJtoAa+h7veyJBw/3DgSY8InMH8szJIed8vRn
# HCz8e+eIHernTqOhwSNTyo36Rc8J0F6v0LBCBKL5pmyTZ9co3EZTsIbQ5ShGLies
# hk9VUgzkAyz7apCQMG6H81kwnfp+1pez6CGXfvjSE/MIt1NtUrRFkJ9IAEpHZhEn
# KWaol+TTBoFKovmEpxFHFAmCn4TtVXj+AZodUAiFABAwRu233iNGu8QtVJ+vHnhB
# MXfMm987g5OhYQK1HQ2x/PebsgHOIktU//kFw8IgCwIDAQABo4IBqzCCAacwDwYD
# VR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUIzT42VJGcArtQPt2+7MrsMM1sw8wCwYD
# VR0PBAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMIGYBgNVHSMEgZAwgY2AFA6sgmBA
# VieX5SUT/CrhClOVWeSkoWOkYTBfMRMwEQYKCZImiZPyLGQBGRYDY29tMRkwFwYK
# CZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQDEyRNaWNyb3NvZnQgUm9vdCBD
# ZXJ0aWZpY2F0ZSBBdXRob3JpdHmCEHmtFqFKoKWtTHNY9AcTLmUwUAYDVR0fBEkw
# RzBFoEOgQYY/aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVj
# dHMvbWljcm9zb2Z0cm9vdGNlcnQuY3JsMFQGCCsGAQUFBwEBBEgwRjBEBggrBgEF
# BQcwAoY4aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNyb3Nv
# ZnRSb290Q2VydC5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEF
# BQADggIBABCXisNcA0Q23em0rXfbznlRTQGxLnRxW20ME6vOvnuPuC7UEqKMbWK4
# VwLLTiATUJndekDiV7uvWJoc4R0Bhqy7ePKL0Ow7Ae7ivo8KBciNSOLwUxXdT6uS
# 5OeNatWAweaU8gYvhQPpkSokInD79vzkeJkuDfcH4nC8GE6djmsKcpW4oTmcZy3F
# UQ7qYlw/FpiLID/iBxoy+cwxSnYxPStyC8jqcD3/hQoT38IKYY7w17gX606Lf8U1
# K16jv+u8fQtCe9RTciHuMMq7eGVcWwEXChQO0toUmPU8uWZYsy0v5/mFhsxRVuid
# cJRsrDlM1PZ5v6oYemIp76KbKTQGdxpiyT0ebR+C8AvHLLvPQ7Pl+ex9teOkqHQ1
# uE7FcSMSJnYLPFKMcVpGQxS8s7OwTWfIn0L/gHkhgJ4VMGboQhJeGsieIiHQQ+kr
# 6bv0SMws1NgygEwmKkgkX1rqVu+m3pmdyjpvvYEndAYR7nYhv5uCwSdUtrFqPYmh
# dmG0bqETpr+qR/ASb/2KMmyy/t9RyIwjyWa9nR2HEmQCPS2vWY+45CHltbDKY7R4
# VAXUQS5QrJSwpXirs6CWdRrZkocTdSIvMqgIbqBbjCW/oO+EyiHW6x5PyZruSeD3
# AWVviQt9yGnI5m7qp5fOMSn/DsVbXNhNG6HY+i+ePy5VFmvJE6P9MYIElzCCBJMC
# AQEwgZAweTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEjMCEG
# A1UEAxMaTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0ECEzMAAAEKLHmu13l7pqwA
# AQAAAQowCQYFKw4DAhoFAKCBsDAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAc
# BgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUMKFv
# 1v/Fzj2d6MQR/I6fWzGRAWQwUAYKKwYBBAGCNwIBDDFCMECgFoAUAFAAbwB3AGUA
# cgBTAGgAZQBsAGyhJoAkaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL1Bvd2VyU2hl
# bGwgMA0GCSqGSIb3DQEBAQUABIIBAI71dqBXaOB0BuAyluhd/W5eHiqPKGLOyOD6
# Q0tVPuE04hRbPXGU50/pYr1LKfGNxk5nAC5d6R19gF+hIvNaQud6AhSsQw80QQJR
# 7MRv5xlRurNT2rBCtWCAxEjgwi2j0uyzBwrBG/Gqtzl8NucbIvwsrVsNrbimuu/b
# e2A96sRmr7fL0GSJMgx6frw7n1DuvtYMYYQNU3UCP4amqooQ2P2ximpLq+8WmITp
# dON9ydh2yomJi99iUOinoK8hjJnpKfxbnrdMbzkD9+3ibTWidt4exarqudQK3vXo
# 9fRa0Wb9GUN2u1QTeGL/cFKJ6FZ9UXRIE4bPYJlRU7R+N1FKA1ChggIoMIICJAYJ
# KoZIhvcNAQkGMYICFTCCAhECAQEwgY4wdzELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# AhMzAAAAkkyir1UnCC51AAAAAACSMAkGBSsOAwIaBQCgXTAYBgkqhkiG9w0BCQMx
# CwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0xNjA0MTkxODI0MjZaMCMGCSqG
# SIb3DQEJBDEWBBSft5g10FGyxRQx9k0rATBaUVIgXzANBgkqhkiG9w0BAQUFAASC
# AQCttIoyE6ehuDJLT6egkILwdX5+jHiKDQKa0rahLFvPDdhUOxF1B3MoKdcFvRkW
# WdiJFESq1UiBotCK42wQHGa1XtXjYVc808EMB7ojadbfAB1nOEMmhU1YZKLuZqSp
# 7V5Y8HX0jXPW/A9AeH72ukusK3vUJRCfsgfTCvbobCAoj5huuxs65eDb7/Ohc7eM
# xtN8AiA0YvakstI5FajpPnpeWO6SdsAAQchGMvxnc7thu0cDlGBNVF0HPjelClvn
# s0Dz3TPIwja6wRmy1WtmOgWoJTxdXJVdEI6YpuNdBHVlBMDliJnk1HBD/vNXfAAQ
# JxvtzGKnDgXTOpwo6iYS5LWp
# SIG # End signature block
