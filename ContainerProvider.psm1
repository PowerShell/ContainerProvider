###
### SEARCH VARS
### Techniques are pulled from: https://azure.microsoft.com/en-us/documentation/articles/search-chrome-postman/
### Index name must only contain lowercase letters, digits or dashes, cannot start or end with dashes and is limited to 128 characters.
###
$fwdLink = "http://go.microsoft.com/fwlink/?LinkID=627586&clcid=0x409"
$publicQueryKey = '82E9CC3E0342EA5C9B95ED909FC8E039'
$indexName = 'pshct-pub-srch-index'
$apiVersionQP = 'api-version=2015-02-28'
[System.Version] $minVersion = '0.0.0.0'

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
        [System.Version]$Version = $minVersion,

        [parameter(Mandatory=$false)]
        [System.String]$SearchKey = $publicQueryKey
    )
    
    $result_Search = Find $Name $Version $SearchKey

    # Handle empty search result
    if(!$result_Search)
    {
        Write-Error "No such module found."
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
                            [[-Version] <Version>] [-SearchKey [String]]

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
        [System.String]$Version = $minVersion,

        [parameter(Mandatory=$true)]
        [System.String]$Destination,

        [parameter(Mandatory=$false)]
        [System.String]$SearchKey = $publicQueryKey
    )

    if(-not (CheckDestination $Destination))
    {
        return
    }

    $result_Search = Find $Name $Version $SearchKey

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

    Save-ContainerImageFile $maxToken $Destination
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
        [System.String]$Version = $minVersion,

        [parameter(Mandatory=$false)]
        [System.String]$SearchKey = $publicQueryKey
    )

    $Destination = $env:TEMP + "\" + $Name + ".wim"

    Write-Verbose "Saving to $Destination"

    try
    {
        Save-ContainerImage -Name $Name `
                                -Version $Version `
                                -Destination $Destination `
                                -SearchKey $SearchKey
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

    $Destination = $env:TEMP + "\" + $Name + ".wim"

    Write-Verbose "Saving to $Destination"

    try
    {
        Save-ContainerImageFile -downloadURL $SasToken `
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

    "Installed in " + $differenceInstallTime.Hours + " hours, " + $differenceInstallTime.Minutes + " minutes, " + $differenceInstallTime.Seconds + " seconds."

    # Clean up
    Write-Verbose "Removing the installer: $Destination"
    rm $Destination
    Write-Verbose "All Done"
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
                    @{Expression={$_.description};Label="Description";width=60}
        
    $searchResults | Format-Table $formatting
}

###
### SUMMARY: Finds the container image entries on Azure Search
### PARAMS:
### 1. Name: Name of the image
### 2. Version: Version of the image
###
function Find
{
    param($Name, $Version, $queryKey=$publicQueryKey)
    
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

    # Headers
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
        $VersionToUseInQuery = if ($Version -ne $minVersion) { $Version } else { "*" }
        $responseValue = $responseValue | ? { ($_.name -like "$NameToUseInQuery") -and ($_.version -like "$VersionToUseInQuery") }

        $responseClassArray = @()
        foreach($element in $responseValue)
        {
            $item = [ContainerImageItem]::new()
            $item.Name = $element.Name
            $item.description = $element.Description
            $item.version = $element.version
            $item.sasToken = $element.sastoken

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
### SUMMARY: Download the file given the URI to the given location
###
function Save-ContainerImageFile
{
    param($downloadURL, $destination)

    $startTime = Get-Date

    Write-Verbose $downloadURL

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

#endregion Helper Functions

################################################################################

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
        [string] $maximumVersion
    )

    $null = write-debug "In $($ProviderName)- Find-Package"

    if ([string]::IsNullOrWhiteSpace($requiredVersion)) {
        $requiredVersion = [System.Version]::new("0.0.0.0")
        $null = write-debug "version is null"
    }
    else {
        $requiredVersion = [System.Version]::new($requiredVersion)
    }
		    	    	    
    foreach($container in (Find -Name $names[0] -Version $requiredVersion))
    {
        if ($request.IsCancelled)
        {
            $null = Write-Verbose "Request has been cancelled."
            return
        }

        $fastPackageReference = $container.Name + $separator +
                                    $container.version + $separator + 
                                    $container.Description + $separator + 
                                    $container.sasToken

        $containerSWID = @{
            name = $container.Name
            version = $container.Version
            versionScheme = "semver"
            summary = $container.Description
            source = "Azure Public"
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

    $sasToken = $resultArray[3]

    Save-ContainerImageFile $sasToken $destLocation    
}

function Install-Package
{
    param(
        [string] $fastPackageReference
    )   	

    [string[]] $splitterArray = @("$separator")
    
    [string[]] $resultArray = $fastPackageReference.Split($splitterArray, [System.StringSplitOptions]::None);

    $name = $resultArray[0]
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
            versionScheme = "semver"
            source = "Azure Public"
            fastPackageReference = $container.Name
        }

        New-SoftwareIdentity @containerSWID
    }
}

##########################################################################
