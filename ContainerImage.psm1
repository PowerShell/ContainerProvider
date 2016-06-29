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

    Add-Type -AssemblyName System.Net.Http
    
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
    
    Add-Type -AssemblyName System.Net.Http
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

   Add-Type -AssemblyName System.Net.Http
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
# MIIarwYJKoZIhvcNAQcCoIIaoDCCGpwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUhEyF30SeN3pbXMdwtp6G5j74
# O1egghWCMIIEwzCCA6ugAwIBAgITMwAAAK9TR3dsG/GjAgAAAAAArzANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTYwNTAzMTcxMzI1
# WhcNMTcwODAzMTcxMzI1WjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OjMxQzUtMzBCQS03QzkxMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvIU6bFARsNjT
# YwC3p63ceKHrpHQuCZTbNDUUaayYlNptTs9au9YI+P9IBOKErcKjXkxftzeQaum8
# 6O7IGQlJPvqr0Cms32bitA6yECmWddujRimd4ULql8Imc452jaG1pjiPfq8uZcTg
# YHkJ5/AMQ+K2NuGTLEw4//BTmnBMOugRKUuUZcVQZG+E9wot5slnIe1p/VgYpt8D
# ejA4crXFzAeAXtj4XEY7NdE351GaIET0Y1LeKdWjnwhz2dqjhX2BJE/HDid/HYv3
# bnrgHBlHfmOTkaB799B8amERbJjNJfqrCKofWxUBWq7R1iStUCFjSSvt+Q/OS2ao
# YsLXObA2rwIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFGgYUtBYbEj/U4U9IDez4/ZM
# dPF4MB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAIz32N/DMfk74OzCmb8uSgdkrVDlMU0+O4OWsClrjoUq0o6w
# 2qNxSX+nzxxbt7e7paBO+0pyf2m4XaGBLfuZW8lBRC2mR+U5K1wXzZTqy/3v1dIK
# yngU2cPT1L8yaC5v6FkpDljzBfslTmPvPljhN41uKTifBPqxpO+H41lCVaG/zN6H
# DovSoSt8jMOh01+9VCUsbccY6J7D9iT3erE1a0FVXy7cn9mDckXaeAOfz8cMJWlc
# NWqN1J+DjUWpArxwQjVX+gxC1CUx8Z1aA+HSBfbCXaOAtLRni3VUf1Wje/mHZevD
# fUkM2gKd9TcEu2IN1pDcWnjcSb5KLOPfSOU7Xz8wggTsMIID1KADAgECAhMzAAAB
# Cix5rtd5e6asAAEAAAEKMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBMB4XDTE1MDYwNDE3NDI0NVoXDTE2MDkwNDE3NDI0NVowgYMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIx
# HjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJL8bza74QO5KNZG0aJhuqVG+2MWPi75R9LH7O3HmbEm
# UXW92swPBhQRpGwZnsBfTVSJ5E1Q2I3NoWGldxOaHKftDXT3p1Z56Cj3U9KxemPg
# 9ZSXt+zZR/hsPfMliLO8CsUEp458hUh2HGFGqhnEemKLwcI1qvtYb8VjC5NJMIEb
# e99/fE+0R21feByvtveWE1LvudFNOeVz3khOPBSqlw05zItR4VzRO/COZ+owYKlN
# Wp1DvdsjusAP10sQnZxN8FGihKrknKc91qPvChhIqPqxTqWYDku/8BTzAMiwSNZb
# /jjXiREtBbpDAk8iAJYlrX01boRoqyAYOCj+HKIQsaUCAwEAAaOCAWAwggFcMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBSJ/gox6ibN5m3HkZG5lIyiGGE3
# NDBRBgNVHREESjBIpEYwRDENMAsGA1UECxMETU9QUjEzMDEGA1UEBRMqMzE1OTUr
# MDQwNzkzNTAtMTZmYS00YzYwLWI2YmYtOWQyYjFjZDA1OTg0MB8GA1UdIwQYMBaA
# FMsR6MrStBZYAck3LjMWFrlMmgofMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY0NvZFNpZ1BDQV8w
# OC0zMS0yMDEwLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljQ29kU2lnUENBXzA4LTMx
# LTIwMTAuY3J0MA0GCSqGSIb3DQEBBQUAA4IBAQCmqFOR3zsB/mFdBlrrZvAM2PfZ
# hNMAUQ4Q0aTRFyjnjDM4K9hDxgOLdeszkvSp4mf9AtulHU5DRV0bSePgTxbwfo/w
# iBHKgq2k+6apX/WXYMh7xL98m2ntH4LB8c2OeEti9dcNHNdTEtaWUu81vRmOoECT
# oQqlLRacwkZ0COvb9NilSTZUEhFVA7N7FvtH/vto/MBFXOI/Enkzou+Cxd5AGQfu
# FcUKm1kFQanQl56BngNb/ErjGi4FrFBHL4z6edgeIPgF+ylrGBT6cgS3C6eaZOwR
# XU9FSY0pGi370LYJU180lOAWxLnqczXoV+/h6xbDGMcGszvPYYTitkSJlKOGMIIF
# vDCCA6SgAwIBAgIKYTMmGgAAAAAAMTANBgkqhkiG9w0BAQUFADBfMRMwEQYKCZIm
# iZPyLGQBGRYDY29tMRkwFwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQD
# EyRNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMTAwODMx
# MjIxOTMyWhcNMjAwODMxMjIyOTMyWjB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSMwIQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBD
# QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJyWVwZMGS/HZpgICBC
# mXZTbD4b1m/My/Hqa/6XFhDg3zp0gxq3L6Ay7P/ewkJOI9VyANs1VwqJyq4gSfTw
# aKxNS42lvXlLcZtHB9r9Jd+ddYjPqnNEf9eB2/O98jakyVxF3K+tPeAoaJcap6Vy
# c1bxF5Tk/TWUcqDWdl8ed0WDhTgW0HNbBbpnUo2lsmkv2hkL/pJ0KeJ2L1TdFDBZ
# +NKNYv3LyV9GMVC5JxPkQDDPcikQKCLHN049oDI9kM2hOAaFXE5WgigqBTK3S9dP
# Y+fSLWLxRT3nrAgA9kahntFbjCZT6HqqSvJGzzc8OJ60d1ylF56NyxGPVjzBrAlf
# A9MCAwEAAaOCAV4wggFaMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFMsR6MrS
# tBZYAck3LjMWFrlMmgofMAsGA1UdDwQEAwIBhjASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBT90TFO0yaKleGYYDuoMW+mPLzYLTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTAfBgNVHSMEGDAWgBQOrIJgQFYnl+UlE/wq4QpTlVnk
# pDBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEE
# SDBGMEQGCCsGAQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY3Jvc29mdFJvb3RDZXJ0LmNydDANBgkqhkiG9w0BAQUFAAOCAgEAWTk+
# fyZGr+tvQLEytWrrDi9uqEn361917Uw7LddDrQv+y+ktMaMjzHxQmIAhXaw9L0y6
# oqhWnONwu7i0+Hm1SXL3PupBf8rhDBdpy6WcIC36C1DEVs0t40rSvHDnqA2iA6VW
# 4LiKS1fylUKc8fPv7uOGHzQ8uFaa8FMjhSqkghyT4pQHHfLiTviMocroE6WRTsgb
# 0o9ylSpxbZsa+BzwU9ZnzCL/XB3Nooy9J7J5Y1ZEolHN+emjWFbdmwJFRC9f9Nqu
# 1IIybvyklRPk62nnqaIsvsgrEA5ljpnb9aL6EiYJZTiU8XofSrvR4Vbo0HiWGFzJ
# NRZf3ZMdSY4tvq00RBzuEBUaAF3dNVshzpjHCe6FDoxPbQ4TTj18KUicctHzbMrB
# 7HCjV5JXfZSNoBtIA1r3z6NnCnSlNu0tLxfI5nI3EvRvsTxngvlSso0zFmUeDord
# EN5k9G/ORtTTF+l5xAS00/ss3x+KnqwK+xMnQK3k+eGpf0a7B2BHZWBATrBC7E7t
# s3Z52Ao0CW0cgDEf4g5U3eWh++VHEK1kmP9QFi58vwUheuKVQSdpw5OPlcmN2Jsh
# rg1cnPCiroZogwxqLbt2awAdlq3yFnv2FoMkuYjPaqhHMS+a3ONxPdcAfmJH0c6I
# ybgY+g5yjcGjPa8CQGr/aZuW4hCoELQ3UAjWwz0wggYHMIID76ADAgECAgphFmg0
# AAAAAAAcMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0wNzA0MDMxMjUzMDlaFw0yMTA0MDMx
# MzAzMDlaMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xITAf
# BgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJ+hbLHf20iSKnxrLhnhveLjxZlRI1Ctzt0YTiQP7tGn
# 0UytdDAgEesH1VSVFUmUG0KSrphcMCbaAGvoe73siQcP9w4EmPCJzB/LMySHnfL0
# Zxws/HvniB3q506jocEjU8qN+kXPCdBer9CwQgSi+aZsk2fXKNxGU7CG0OUoRi4n
# rIZPVVIM5AMs+2qQkDBuh/NZMJ36ftaXs+ghl3740hPzCLdTbVK0RZCfSABKR2YR
# JylmqJfk0waBSqL5hKcRRxQJgp+E7VV4/gGaHVAIhQAQMEbtt94jRrvELVSfrx54
# QTF3zJvfO4OToWECtR0Nsfz3m7IBziJLVP/5BcPCIAsCAwEAAaOCAaswggGnMA8G
# A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFCM0+NlSRnAK7UD7dvuzK7DDNbMPMAsG
# A1UdDwQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADCBmAYDVR0jBIGQMIGNgBQOrIJg
# QFYnl+UlE/wq4QpTlVnkpKFjpGEwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5ghB5rRahSqClrUxzWPQHEy5lMFAGA1UdHwRJ
# MEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRIMEYwRAYIKwYB
# BQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0Um9vdENlcnQuY3J0MBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEB
# BQUAA4ICAQAQl4rDXANENt3ptK132855UU0BsS50cVttDBOrzr57j7gu1BKijG1i
# uFcCy04gE1CZ3XpA4le7r1iaHOEdAYasu3jyi9DsOwHu4r6PCgXIjUji8FMV3U+r
# kuTnjWrVgMHmlPIGL4UD6ZEqJCJw+/b85HiZLg33B+JwvBhOnY5rCnKVuKE5nGct
# xVEO6mJcPxaYiyA/4gcaMvnMMUp2MT0rcgvI6nA9/4UKE9/CCmGO8Ne4F+tOi3/F
# NSteo7/rvH0LQnvUU3Ih7jDKu3hlXFsBFwoUDtLaFJj1PLlmWLMtL+f5hYbMUVbo
# nXCUbKw5TNT2eb+qGHpiKe+imyk0BncaYsk9Hm0fgvALxyy7z0Oz5fnsfbXjpKh0
# NbhOxXEjEiZ2CzxSjHFaRkMUvLOzsE1nyJ9C/4B5IYCeFTBm6EISXhrIniIh0EPp
# K+m79EjMLNTYMoBMJipIJF9a6lbvpt6Znco6b72BJ3QGEe52Ib+bgsEnVLaxaj2J
# oXZhtG6hE6a/qkfwEm/9ijJssv7fUciMI8lmvZ0dhxJkAj0tr1mPuOQh5bWwymO0
# eFQF1EEuUKyUsKV4q7OglnUa2ZKHE3UiLzKoCG6gW4wlv6DvhMoh1useT8ma7kng
# 9wFlb4kLfchpyOZu6qeXzjEp/w7FW1zYTRuh2Povnj8uVRZryROj/TGCBJcwggST
# AgEBMIGQMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xIzAh
# BgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBAhMzAAABCix5rtd5e6as
# AAEAAAEKMAkGBSsOAwIaBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFCnf
# 8gNYPWZpakYnLulOVI6tN7xxMFAGCisGAQQBgjcCAQwxQjBAoBaAFABQAG8AdwBl
# AHIAUwBoAGUAbABsoSaAJGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9Qb3dlclNo
# ZWxsIDANBgkqhkiG9w0BAQEFAASCAQBXJZUTztaRAvpsN06XjraLCv3S5sNZaJHS
# Yu/AAy1Es98KXGMibNFdM3IPvQEiVrYKSQKMwNOZU0oeFOehDgiV1JdNNKB6so7i
# 6Z9PQwlUghF6Blx9F8aJS8prFzqgqjzS6k5Q30jyJXexty4stjr6MU4R8WHWxyyG
# 8zYMskSG647VIaCrFe7m4oEjoAuzWYwyO3QMBL9daq3RgF7sfT92Zaxkx5FPMcqa
# oSZai6YtjtdYrH/3qQb1o1O54yTGBvFGIRsfcNAi5JtIGPADYyXCWmqfsjckpk7n
# dx3HzQVfQO0UTiqcAFieYoglOTZQW222aYWzawEVbWvD1sv3qxsFoYICKDCCAiQG
# CSqGSIb3DQEJBjGCAhUwggIRAgEBMIGOMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xITAfBgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QQITMwAAAK9TR3dsG/GjAgAAAAAArzAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkD
# MQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTYwNjI4MTY1MzQ4WjAjBgkq
# hkiG9w0BCQQxFgQU6t6JulCaS0YjAEOQxaa0DvpMZ/AwDQYJKoZIhvcNAQEFBQAE
# ggEApEkTkl859ZLFfXAZPsxkyDdbKfpRclUFLOactrY2L5EfPmKL185mP8ZzcA/p
# lk0YKR4Dh513q7dLG/lPx2sKTh9mbOToK4qz6eeJV//Np9/+m4GJnRwydBS5JMSq
# t6f5NItj/sYV1/sMq9McfL8UhAtUzXWnEsiparth4MXEVTmRa+8EsaTn2TM0nxid
# Jg2P7V/lv6F7s2yjONAtg3kt+uGLM1ilhlClCuyOppkqLGU0oMC75yz6WCyaR2cG
# FeulvLI4Nm4BH/xSUv0SeeRJN7EUc8dDMHgQxkTox+ErgIxvuWuF0Y5k1O6weq6G
# l63xIr1phQ8YfWuubOSVPdVTsg==
# SIG # End signature block
