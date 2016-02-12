### 
### SOURCES
###
$script:location_modules = "$env:LOCALAPPDATA\containerprovider"
$script:file_modules = "$script:location_modules\sources.txt"
$script:ContainerSources = $null
# Wildcard pattern matching configuration.
$script:wildcardOptions = [System.Management.Automation.WildcardOptions]::CultureInvariant -bor `
                          [System.Management.Automation.WildcardOptions]::IgnoreCase

###
### SEARCH VARS for LIMITED RELEASE SEARCH
###
$script:QueryKey = 'QueryKey'
$script:IndexName = 'IndexName'
$Script:PSGalleryModuleSource="PSGallery"

###
### VARS for LOCAL SEARCH
###

$apiVersionQP = 'api-version=2015-02-28'
$script:location = 'Location'
[System.Version] $minVersion = '0.0.0.0'

#$script:RegisteredPackageSourcesFilePath = Microsoft.PowerShell.Management\Join-Path -Path $script:LocalPath -ChildPath "ContainerProvider.ps1xml"

#region Functions

###
### SUMMARY: Finds the container image from the Azure Search Service
### PARAMS:
### 1. Name: Optional param: Name of the image
### 2. Version: Optional param : Version of the image
###
function Find-ContainerImage
{
    <#
        .SYNOPSIS
        Finds the container image from an online gallery that match specified criteria.

        .SYNTAX
        Find-ContainerImage [[-Name] <String>] [[-Version] <Version>] [-SearchKey [String]]

        .DESCRIPTION
        Find-ContainerImage finds the images from the online gallery that match specified criteria.
        For each module found, Find-ContainerImage returns a 

        If the Version is not specified, all versions of the image are returned
        If the Version parameter is specified, Find-ContainerImage only returns the version of 
        the image that exactly matches the specified version
        
        .EXAMPLE
        Find-ContainerImage -Name ImageName

        .EXAMPLE
        Find-ContainerImage -Version 1.2.3.5

        .EXAMPLE
        Find-ContainerImage -Name ImageName -Version 1.2.3.4
    #>

    [cmdletbinding()]
    
    # Handle the input parameters
    param
    (
        [parameter(Mandatory=$false)]
        [System.String]$Name,

        [parameter(Mandatory=$false)]
        [System.Version]$Version,

        [parameter(Mandatory=$false)]
        [System.String]$Source
    )
    
    $result_Search = Find $Name $Version $Source

    # Handle empty search result
    if(!$result_Search)
    {
        return
    }

    return $result_Search
}

###
### SUMMARY: Downloads and saves the container image
### PARAMS:
### 1. Name: Mandatory param: Name of the image
### 2. Version: Optional param: Version of the image
### 3. Destination: Mandatory param: Destiation where the file needs to be saved
### 4. SearchKey: Searches using this search key
### 
### This function will first find the image based on given params
### If version is provided, save that particular version
### Else save the latest version
###
function Save-ContainerImage
{
    <#
        .SYNOPSIS
        Saves a container image without installing it.

        .SYNTAX
        Save-ContainerImage [[-Name] <String>] [[-Destination] <String>] 
                            [[-Version] <Version>]

        .DESCRIPTION
        The Save-ContainerImage cmdlet lets you save a container image locally without installing it.
        This lets you inspect the container image  before you install, helping to minimize the risks
        of malicious code or malware on your system

        As a best practice, when you have finished evaluating a container image for potential risks,
        and before you install the image for use, dleete the image from the path to which you have saved.
        
        .EXAMPLE
        Save-ContainerImage -Name ImageName -Destination C:\temp\ImageName.wim

        .EXAMPLE
        Save-ContainerImage -Name ImageName -Version 1.2.3.5 -Destination C:\temp\ImageName.wim
    #>

    [cmdletbinding()]
    
    # Handle the input parameters
    param
    (
        [parameter(Mandatory=$true)]
        [System.String]$Name,

        [parameter(Mandatory=$false)]
        [System.String]$Version,

        [parameter(Mandatory=$false)]
        [System.String]$Source,

        [parameter(Mandatory=$true)]
        [System.String]$Destination
    )

    if(-not (CheckDestination $Destination))
    {
        return
    }

    $result_Search = Find $Name $Version $Source

    # Handle empty search result
    if(!$result_Search)
    {
        throw [System.IO.FileNotFoundException] "No such module found."
    }

    [System.Version] $maxVersion = '0.0.0.0'
    $maxToken, $maxName

    if($Version -ne $minVersion)
    {
        # If version is provided, download that specific version
        $image = $result_Search[0]
        $maxName = $image.name
        $maxToken = $image.sastoken
        $maxVersion = $image.version
    }
    else
    {
        # Else download the latest version
        ForEach($image in $result_Search)
        {
            if($image.version -gt $maxVersion)
            {
                $maxName = $image.name
                $maxToken = $image.sastoken
                $maxVersion = $image.version
             }
        }
    }

    Write-Verbose "Downloading $maxName. Version: $maxVersion"

    Save-File $maxToken $Destination
}

###
### SUMMARY: Installs the container image
### PARAMS
### 
### 1. Name: Mandatory param: Name of the image
### 2. Version: Optional param: Version of the image
### 3. Destination: Mandatory param: Destiation where the file needs to be saved
### 4. SearchKey: Searches using this search key
### 
### This function will first find the image based on given params
### If it finds the image, it will be downloaded
### Then it will be installed
###
function Install-ContainerImage
{
    <#
        .SYNOPSIS
        Downloads the image from the cloud and installs them on the local computer

        .SYNTAX
        Install-ContainerImage [[-Name] <String>] [[-Destination] <String>] 
                            [[-Version] <Version>] [-SearchKey [String]]

        .DESCRIPTION
        The Install-ContainerImage gets the container image that meets the specified cirteria from the cloud.
        It saves the image locally and then installs it
        
        .EXAMPLE
        Install-ContainerImage -Name ImageName

        .EXAMPLE
        Install-ContainerImage -Name ImageName -Version 1.2.3.5
    #>

    [cmdletbinding()]
    
    # Handle the input parameters
    param
    (
        [parameter(Mandatory=$true)]
        [System.String]$Name,

        [parameter(Mandatory=$false)]
        [System.String]$Version,

        [parameter(Mandatory=$false)]
        [System.String]$Source
    )

    $Destination = $env:TEMP + "\" + $Name + ".wim"

    Write-Verbose "Saving to $Destination"

    try
    {
        Save-ContainerImage -Name $Name `
                                -Version $Version `
                                -Destination $Destination                                
    }
    catch
    {
        Write-Error "Unable to download."
        if((Test-Path $Destination))
        {
            Write-Verbose "Removing the installer: $Destination"
            rm $Destination
        }
        return        
    }

    $startInstallTime = Get-Date

    Install-ContainerOSImage -WimPath $Destination `
                             -Force

    $endInstallTime = Get-Date
    $differenceInstallTime = New-TimeSpan -Start $startInstallTime -End $endInstallTime
    $installTime = "Installed in " + $differenceInstallTime.Hours + " hours, " + $differenceInstallTime.Minutes + " minutes, " + $differenceInstallTime.Seconds + " seconds."
    Write-Verbose $installTime

    # Clean up
    Write-Verbose "Removing the installer: $Destination"
    rm $Destination

    Write-Verbose "All Done"
}

###
### SUMMARY: Installs the container image
### PARAMS
### 
### 1. Name: Mandatory param: Name of the image
### 2. Version: Optional param: Version of the image
### 3. Destination: Mandatory param: Destiation where the file needs to be saved
### 4. SearchKey: Searches using this search key
### 
### This function will first find the image based on given params
### If it finds the image, it will be downloaded
### Then it will be installed
###
function Install-ContainerImageHelper
{
    <#
        .SYNOPSIS
        Downloads the image from the cloud and installs them on the local computer

        .SYNTAX
        Install-ContainerImage [[-Name] <String>] [[-Destination] <String>] 
                            [[-Version] <Version>] [-SearchKey [String]]

        .DESCRIPTION
        The Install-ContainerImage gets the container image that meets the specified cirteria from the cloud.
        It saves the image locally and then installs it
        
        .EXAMPLE
        Install-ContainerImage -Name ImageName

        .EXAMPLE
        Install-ContainerImage -Name ImageName -Version 1.2.3.5
    #>

    # Handle the input parameters
    param
    (
        [parameter(Mandatory=$true)]
        [System.String]$SasToken,

        [parameter(Mandatory=$true)]
        [System.String]$Name
    )

    $Destination = $env:TEMP + "\" + $Name

    Write-Verbose "Saving to $Destination"

    try
    {
        Save-File -downloadURL $SasToken `
                        -Destination $Destination
    }
    catch
    {
        Write-Error "Unable to download."
        if((Test-Path $Destination))
        {
            Write-Verbose "Removing the installer: $Destination"
            rm $Destination
        }
        return
    }

    Write-Verbose "Installing $Name"

    $startInstallTime = Get-Date

    Install-ContainerOSImage -WimPath $Destination `
                             -Force

    $endInstallTime = Get-Date

    $differenceInstallTime = New-TimeSpan -Start $startInstallTime -End $endInstallTime

    "Installed in " + $differenceInstallTime.Hours + " hours, " + $differenceInstallTime.Minutes + " minutes, " + $differenceInstallTime.Seconds + " seconds."

    # Clean up
    Write-Verbose "Removing the installer: $Destination"
    rm $Destination
}

#endregion Functions

#region Helper Functions

###
### SUMMARY: Class for display
###
Class ContainerImageItem 
{
    [string] $Name;
    [string] $description;
    [string] $sasToken;
    [string] $source;
    [Version] $version;
}

###
### SUMMARY: Displays the search results
### PARAMS:
### 1. SearchResults
###
function Display-SearchResults
{
    param ($searchResults)

    $formatting = @{Expression={$_.Name};Label="Name";width=20}, `
                    @{Expression={$_.version};Label="Version";width=25}, `
                    @{Expression={$_.source};Label="Source";width=25}, `
                    @{Expression={$_.description};Label="Description";width=60}
        
    $searchResults | Format-Table $formatting
}

###
### SUMMARY: Find 
###
###
function Find
{
    param($Name, $Version, $sources)

    $allSources = Get-Sources $sources

    $allResults = @()

    foreach($theSource in $allSources)
    {
        $location = $theSource.$script:location
        $packageSourceName = $theSource.PackageSourceName

        if($location.StartsWith("http://") -or $location.StartsWith("https://"))
        {
            $queryKey = $theSource.$script:QueryKey
            $index = $theSource.$script:IndexName

            $allResults += Find-Azure $Name $Version $location $index $queryKey $packageSourceName
        }
        elseif($location.StartsWith("\\"))
        {
            $allResults += Find-UNCPath $Name $Version $location $packageSourceName
        }
    }

    return $allResults
}

###
### SUMMARY: Gets the source from where to get the images
### Initializes the variables for find, download and install
### RETURN:
### Returns the type of 
###
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
            $tempHolder.Add($script:location, $location)
            
            $queryKey = $mySource.$script:QueryKey
            $tempHolder.Add($script:QueryKey, $queryKey)
            
            $indexName = $mySource.$script:IndexName
            $tempHolder.Add($script:IndexName, $indexName)

            $packageSourceName = $mySource.Name
            $tempHolder.Add("PackageSourceName", $packageSourceName)
            
            $listOfSources += $tempHolder
        }
    }

    return $listOfSources
}

###
### SUMMARY: Deserializes the PSObject
###
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

###
### SUMMARY: Finds the container image entries on Azure Search
### PARAMS:
### 1. Name: Name of the image
### 2. Version: Version of the image
###
function Find-Azure
{
    param($Name, $Version, $fwdLink, $indexName, $queryKey, $packageSourceName)
    
    if(-not (IsNanoServer))
    {
        Add-Type -AssemblyName System.Net.Http
    }

    $httpPostClient = New-Object System.Net.Http.HttpClient
    $httpPostRequestMsg = New-Object System.Net.Http.HttpRequestMessage(
                            [System.Net.Http.HttpMethod]::Post,
                            $fullUrl)

    # URL
    $resolvedUrl = Resolve-FwdLink $fwdLink

    if (($resolvedUrl.Scheme -ne 'http') -and ($resolvedUrl.Scheme -ne 'https'))
    {
        throw "Unable to get the resolved URL."
    }

    $relativePath = 'indexes/{0}/docs/search?{1}' -f $indexName,$apiVersionQP
    
    $httpPostClient.BaseAddress = New-Object System.Uri($resolvedUrl, $relativePath)
        
    $acceptHeader = New-Object `
                        System.Net.Http.Headers.MediaTypeWithQualityHeaderValue(
                            "application/json")

    $httpPostClient.DefaultRequestHeaders.Accept.Add($acceptHeader)

    # Headers`
    $httpPostRequestMsg.Headers.Add("api-key", $queryKey)
    $httpPostRequestMsg.Headers.Add("charset", "utf-8")

    # Body
    <#
     # Azure search do not support case-insensitive search.
     # Until this is resolved we are doing client side
     # filtering
     
    if($Name)
    {
        $query = "name eq '$Name'"
    }
    
    if($Version -ne $minVersion)
    {
        if($query)
        {
            $query += " and"
        }

        $query += " version eq '$Version'"
    }

    #>
    $httpPostBody = '{
            "filter" : "' + $query + '"
            ,"orderby": "name, version desc"
            }'

    $encoding = [System.Text.Encoding]::ASCII
    $httpPostRequestMsg.Content = New-Object System.Net.Http.StringContent(
                                    $httpPostBody, 
                                    $encoding, 
                                    "application/json")

    try
    {
        $responseTask = $httpPostClient.SendAsync($httpPostRequestMsg)
        $responseContent = $responseTask.Result.Content
        $responseBody = $responseContent.ReadAsStringAsync().Result.ToString()

        if(IsNanoServer)
        {
            $jsonDll = [Microsoft.PowerShell.CoreCLR.AssemblyExtensions]::LoadFrom($PSScriptRoot + "\Json.coreclr.dll")
            $jsonParser = $jsonDll.GetTypes() | ? name -match jsonparser
        
            $response = $jsonParser::FromJson($responseBody)
        }
        else
        {
            $response = $responseBody | ConvertFrom-Json
        }

        $responseValue = $response.value
        # apply filtering for Name and Version.
        # These were not applied when HTTP request is sent
        $NameToUseInQuery = if ($Name) { $Name } else { "*" }
        $VersionToUseInQuery = if ($Version) { $Version } else { "*" }
        $responseValue = $responseValue | ? { ($_.name -like "$NameToUseInQuery") -and ($_.version -like "$VersionToUseInQuery") }

        $responseClassArray = @()
        foreach($element in $responseValue)
        {
            $item = [ContainerImageItem]::new()
            $item.Name = $element.Name
            $item.description = $element.Description
            $item.version = $element.version
            $item.sasToken = $element.sastoken
            $item.source = $packageSourceName

            $responseClassArray += $item
        }

        return $responseClassArray
    }
    catch [System.Net.Http.HttpRequestException]
    { 
        Write-Host "Error:System.Net.HttpRequestException"
    } 
    catch [Exception]
    {
        Write-Host "$_.Message"
    } 
    finally 
    {
    }
}

###
### SUMMARY: Finds the container image entries from the share directory
### PARAMS:
### 1. Name: Name of the image
### 2. Version: Version of the image
###
function Find-UNCPath
{
    param($Name, $Version, $localPath, $packageSourceName)
    
    $responseArray = @()

    try
    {
        if((-not $Name) -or ($Name.ToLower().Contains("nano")))
        {
            $search_nano = "*nano*.wim"
            
            $images_nano = @()
            $images_nano = Get-ChildItem -Path $localPath `
                                    -ErrorAction SilentlyContinue `
                                    -Filter $search_nano `
                                    -Recurse `
                                    -File `
                                    -Depth 3 `
                                    -Force | % { $_.FullName }

            foreach($nanoImage in $images_nano)
            {
                $version_nano = get-Version $nanoImage

                if((-not $Version) -or ($Version -eq $version_nano))
                {
                    $item_nano = [ContainerImageItem]::new()
                    $item_nano.Name = "NanoServer"
                    $item_nano.version = $version_nano
                    $item_nano.sasToken = $nanoImage
                    $item_nano.description = "Nano " + $version_nano
                    $item_nano.source = $packageSourceName
                    $responseArray += $item_nano
                }
            }
        }

        if((-not $Name) -or ($Name.ToLower().Contains("servercore")))
        {
            $search_server = "*ServerDatacenterCore*.wim"

            $images_server = @()
            $images_server = Get-ChildItem -Path $localPath `
                                    -ErrorAction SilentlyContinue `
                                    -Filter $search_server `
                                    -Recurse `
                                    -File `
                                    -Depth 3 `
                                    -Force | % { $_.FullName }
        
            foreach($serverImage in $images_server)
            {
                $version_server = get-Version $serverImage

                if((-not $Version) -or ($Version -eq $version_server))
                {
                    $item_server = [ContainerImageItem]::new()
                    $item_server.Name = "WindowsServerCore"
                    $item_server.version = $version_server
                    $item_server.sasToken = $serverImage
                    $item_server.description = "Server " + $version_server
                    $item_server.source = $packageSourceName
                    $responseArray += $item_server
                }
            }
        }
    }
    catch
    {
        Write-Error "Unable to access the sub-folders of $localPath"
        return
    }

    return $responseArray
}

###
### SUMMARY: Download the file given the URI to the given location
###
function Save-File
{
    param($downloadURL, $destination)

    $startTime = Get-Date

    Write-Verbose $downloadURL

    if($downloadURL.StartsWith("http://") -or $downloadURL.StartsWith("https://"))
    {
        # Download the file
        if ((IsNanoServer) -or (get-variable pssenderinfo -ErrorAction SilentlyContinue))
        {
            # Use custom Save-HTTPItem function if on Nano or in a remote session
            # This is beacuse BITS service does not work as expected under these circumstances.
            Import-Module "$PSScriptRoot\Save-HttpItem.psm1"
            Save-HTTPItem -Uri $downloadURL `
                            -Destination $destination
        }
        else
        {   
            Start-BitsTransfer -Source $downloadURL `
                            -Destination $destination
        }
    }
    elseif($downloadURL.StartsWith("\\"))
    {
        cp $downloadURL $destination
    }

    $endTime = Get-Date
    $difference = New-TimeSpan -Start $startTime -End $endTime
    $downloadTime = "Downloaded in " + $difference.Hours + " hours, " + $difference.Minutes + " minutes, " + $difference.Seconds + " seconds."
    Write-Verbose $downloadTime
}

###
### SUMMARY: Resolve the fwdlink to get the actual search URL
###
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

###
### SUMMARY: Checks if the system is nano server or not
### Look into the win32 operating system class
### Returns True if running on Nano 
### False otherwise
###
function IsNanoServer
{
    $operatingSystem = Get-CimInstance -ClassName win32_operatingsystem
    $systemSKU = $operatingSystem.OperatingSystemSKU
    return $systemSKU -eq 109
}

###
### SUMMARY: Checks if the given destination is kosher or not
### 1. Check if the user has provider a folder
###          If so, throw an exception, only absolute path with file name is acceptable
### 2. Check if parent path exists
###          If not, create it for the user
### 3. Check if the file exists
###          If so, ask the user for ability to re-write
###
function CheckDestination
{
    param($Destination)

    # Check if entire path is folder structure
    # If folder throw error, ask for file path
    $dest_item = Get-Item $Destination `
                            -ErrorAction SilentlyContinue `
                            -WarningAction SilentlyContinue

    if($dest_item -is [System.IO.DirectoryInfo])
    {
        throw "Please provide file name with path."
    }

    # Check the parent (one minus the whole path) 
    # If the given parent directory doesn't exist
    # create it and return
    $folderPath = Split-Path $Destination
    $isFolderPath = Get-Item $folderPath `
                                -ErrorAction SilentlyContinue `
                                -WarningAction SilentlyContinue 

    if($isFolderPath -isnot [System.IO.DirectoryInfo])
    {
        Write-Verbose "Creating directory structure: $folderPath"
        md $folderPath
        return $true
    }
    
    # If given parent directory exists
    # Check if given file exists
    if((Test-Path $Destination))
    {
        # Check for Read-only file
        $list = dir $Destination | where {$_.attributes -match "ReadOnly"}
        if($list.Count -gt 0)
        {
            Write-Error "Cannot over write read-only file: $Destination"
            return $false
        }

        $title = "Overwrite File"
        $message = "Do you want to overwrite the existing file: $Destination ?"

        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
        "Overwrite the existing file."

        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
        "Do not overwrite the existing file."

        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        $result = $host.ui.PromptForChoice($title, $message, $options, 0) 

        switch ($result)
        {
            0 {
                # User selects Yes.
                return $true
            }

            1 {
                # User selects No.
                Write-Host "Re-run the script with a different Destination"
                Write-Host
                return $false
            }
        }

        return $true
    }

    return $true
}

###
### SUMMARY: Finds the version of the given image
###
### PARAMS:
### 1. Full Path: Path to the image
### 
### RETURNS:
### The version of the image
###
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
#endregion Helper Functions

#region PackageProvider

$Providername = "ContainerProvider"
$separator = "|#|"

<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Find-Package
{
    [CmdletBinding()]
    Param
    (
        [string[]] $names,
        [string] $requiredVersion,
        [string] $minimumVersion,
        [string] $maximumVersion,
        [string] $allVersion
    )

    $options = $request.Options

    $null = write-debug "In $($ProviderName)- Find-Package"

    $sourcesName = $null

    if ($options -and $options.ContainsKey('Source'))
    {
        $sourcesName = $options['Source']
    }

    if ([string]::IsNullOrWhiteSpace($requiredVersion)) {
        $resultContainers = Find -Name $names[0] -Sources $sourcesName
    }
    else {
        $requiredVersion = [System.Version]::new($requiredVersion)
        $resultContainers = Find -Name $names[0] `
                                    -Version $requiredVersion `
                                    -Sources $sourcesName
    }

    foreach($container in $resultContainers)
    {
	    if ($request.IsCancelled)
	    {
		    $null = Write-Verbose "Request has been cancelled."
		    return
	    }

	    $fastPackageReference = $container.Name + $separator +
								    $container.version + $separator + 
								    $container.Description + $separator + 
								    $container.sasToken + $separator + 
								    $container.source

	    $containerSWID = @{
			    name = $container.Name
			    version = $container.Version
			    versionScheme = "MultiPartNumeric"
			    summary = $container.Description
			    source = $container.source
			    fastPackageReference = $fastPackageReference
	    }

	    New-SoftwareIdentity @containerSWID
    }
}

<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Download-Package
{
    param(
        [string] $fastPackageReference,
        [string] $destLocation
    )
    [string[]] $splitterArray = @("$separator")
    
    [string[]] $resultArray = $fastPackageReference.Split($splitterArray, [System.StringSplitOptions]::None);

    if($resultArray.Count -eq 0)
    {
        throw new "Error installing package. Unable to get the package reference"
    }

    $name = $resultArray[0]
    $fileName =  $name + ".wim"
    $destPath = Join-Path $destLocation $fileName
    
    $version = $resultArray[1]
    $desc = $resultArray[2]
    $sasToken = $resultArray[3]
    $origin = $resultArray[4]

    Save-File $sasToken $destPath

    $container = @{
        name = $name
        version = $version
        versionScheme = "MultiPartNumeric"
        summary = $desc
        source = $origin
        fastPackageReference = $fastPackageReference
    }

    Write-Output (New-SoftwareIdentity @container)
}

function Install-Package
{
    param(
        [string] $fastPackageReference
    )

    [string[]] $splitterArray = @("$separator")
    
    [string[]] $resultArray = $fastPackageReference.Split($splitterArray, [System.StringSplitOptions]::None);
    
    if($resultArray.Count -eq 0)
    {
        throw new "Error installing package. Unable to get the package reference"
    }

    $name = $resultArray[0] + ".wim"
    $sasToken = $resultArray[3]
	
	$null = write-debug "Name of the container is $name and sastoken is $sasToken"
	
    Install-ContainerImageHelper -SasToken $sasToken -Name $name
}

function Initialize-Provider
{
    write-debug "In $($Providername) - Initialize-Provider"
}

function Get-PackageProviderName
{
    return $Providername
}

function Get-InstalledPackages
{
    param(
        [string]$name,
        [string]$requiredVersion,
        [string]$minimumVersion,
        [string]$maximumVersion
    )

    $containers = Get-ContainerImage

    if ($containers -eq $null -or $containers.Count -eq 0)
    {
        return
    }

    ForEach($container in Get-ContainerImage)
    {
        if ($request.IsCancelled)
        {
            $null = Write-Verbose "Request has been cancelled."
            return
        }

        $containerSWID = @{
            name = $container.Name
            version = $container.Version
            versionScheme = "MultiPartNumeric"
            source = $container.source
            fastPackageReference = $container.Name
        }

        New-SoftwareIdentity @containerSWID
    }
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
        SourceLocation = "http://go.microsoft.com/fwlink/?LinkID=627586&clcid=0x409"
        Trusted=$false
        Registered= $true
        InstallationPolicy = "Untrusted"
        QueryKey = "82E9CC3E0342EA5C9B95ED909FC8E039"
        IndexName = "pshct-pub-srch-index"
        })

        $script:ContainerSources.Add("ContainerImageGallery", $defaultModuleSource)
        Save-ModuleSources
    }
}

function Get-DynamicOptions
{
    param
    (
        [Microsoft.PackageManagement.MetaProvider.PowerShell.OptionCategory] 
        $category
    )

    switch($category)
    {
        Source  {
                    Write-Output -InputObject (New-DynamicOption -Category $category -Name $script:QueryKey -ExpectedType String -IsRequired $false)
                    Write-Output -InputObject (New-DynamicOption -Category $category -Name $script:IndexName -ExpectedType String -IsRequired $false)
                }
    }
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

    $query_key = $null
    if($Options.ContainsKey($script:QueryKey))
    {
        $query_key = $Options[$script:QueryKey]
    }

    $index_name = $null
    if($Options.ContainsKey($script:IndexName))
    {
        $index_name = $Options[$script:IndexName]
    }

    # Add new module source
    $moduleSource = Microsoft.PowerShell.Utility\New-Object PSCustomObject -Property ([ordered]@{
            Name = $Name
            SourceLocation = $Location            
            Trusted=$Trusted
            Registered= $true
            InstallationPolicy = if($Trusted) {'Trusted'} else {'Untrusted'}
            QueryKey = $query_key 
            IndexName = $index_name
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

    Write-Verbose ($LocalizedData.PackageSourceUnregistered -f ($Name))
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

function New-PackageSourceFromModuleSource
{
    param
    (
        [Parameter(Mandatory=$true)]
        $ModuleSource
    )

    $packageSourceDetails = @{}

    # check if querykey and index name exist
    if ([string]::IsNullOrWhiteSpace($ModuleSource.$script:QueryKey))
    {
        $packageSourceDetails[$script:QueryKey] = $ModuleSource.$script:QueryKey
    }

    if ([string]::IsNullOrWhiteSpace($ModuleSource.$script:IndexName))
    {
        $packageSourceDetails[$script:IndexName] = $ModuleSource.$script:IndexName
    }

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

#endregion PackageProvider