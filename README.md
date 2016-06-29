### Introduction
#### Install a Container image from the online Package repository

The Container OS images for Nano Server and Windows Server Core are now available in an online package repository.  They can be found and installed using the ContainerImage provider of PackageManagement (a.k.a. <a href="http://www.oneget.org">OneGet</a>) PowerShell module.  The provider needs to be installed before using it. The following PowerShell cmdlets can be used to install the provider.
* Install-PackageProvider ContainerImage 
* Import-ContainerImage ContainerImage

Once the provider is installed and imported, you can search, download, or install Container images using PowerShell cmdlets. There are two sets of cmdlets, the first set is specific for the Container OS images, including:
* Find-ContainerImage
* Save-ContainerImage
* Install-ContainerImage

The 2nd set is generic PackageManagement cmdlets, including:
* Find-Package
* Save-Package
* Get-Package

The 2nd set of cmdlets are performed the same as the 1st set, with specifying –provider ContainerImage.  Without specifying the –provider parameter, it may perform slightly slower as PackageManagement will iterate all its providers.  Below is the detailed usage. For a complete usage of the cmdlets, use get-help <cmdlet>. For the general usage of the Containers, read the<a href="https://msdn.microsoft.com/en-us/virtualization/windowscontainers/management/manage_images"> container MSDN doc</a>.

#### Search a Container Image
Both Find-ContainerImage and Find-Package search and return a list of Container images available in the online repository. 

##### Example 1: Find the latest version of all available Container images. 
	Find-ContainerImage
	Find-Package –provider ContainerImage
    
##### Example 2: Search by the image name. The –name parameter accepts wildcard.
	Find-ContainerImage -Name *nano*
	Find-Package –provider ContainerImage -Name *nano *
   
##### Example 3: Search by version, according to –RequiredVersion, -MinimumVersion, and –MaximumVersion requirements. With –AllVersions parameter, all available versions of a Container image are returned. Without it, only the latest version is returned.
    Find-ContainerImage -Name *nano* -RequiredVersion 10.0.14300.1000
    Find-Package –provider ContainerImage –AllVersions -Name *nano*

#### Install a Container
Install-ContainerImage installs a Container image to the local machine. Both cmdlets accept pipeline result from search cmdlets. The operating system:
1.must have the Containers Package (i.e. Microsoft-NanoServer-Containers-Package Windows package) installed
2.version must match the version of Container OS image, i.e. 10.0.14300.1000
Otherwise, the installation will fail.

##### Example 1: Install the latest version of a Container image to the local machine.
	Install-ContainerImage -Name NanoServer

##### Example 2: Install a Container image with pipeline result from the search cmdlets.
	Find-ContainerImage *nano* | Install-ContainerImage
	Find-ContainerImage -Name *windowsServercore * |Install-ContainerImage

#### Download a Container image
You can download and save a Container image without installation, using Save-ContainerImage or Save-Package. Both cmdlets accept pipeline result from the search cmdlets.

##### Example 1: Download and save a Container image to a directory that matches the wildcard path. The latest version will be saved if you do not specify the version requirements.
	Save-ContainerImage -Name NanoServer -Path C:\t*p\
	Save-Package –provider ContainerImage  -Name WindowsServerCore -Path .\temp -MinimumVersion 10.0.14300.1000

##### Example 2: Download and save a ContainerImage from the search cmdlets.
	Find-ContainerImage -Name *nano* -MaximumVersion 10.2 -MinimumVersion 1.0 | Save-ContainerImage -Path c:\
	Find-Package -provider ContainerImage -Name *shield* -Culture es-es | Save-Package -Path .

#### Inventory installed Container images
You can inventory what Container images are installed, using PackageManagement Get-Package cmdlet. 

##### Example 1: Inventory what Container images are installed in the local machine.
	Get-Package –provider ContainerImage

### ContainerImage cmdlets
	- Find-ContainerImage [[-Name] <string[]>] [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-AllVersions] [-source <string>] [<CommonParameters>]
	- Save-ContainerImage [-Name] <string[]> -Path <string> [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Force] [-source <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
	- Save-ContainerImage [-Name] <string[]> -LiteralPath <string> [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Force] [-source <string>] [-WhatIf] [-Confirm]  [<CommonParameters>]
	- Install-ContainerImage [-Force] [-Source <string>] [-WhatIf] [-Confirm]  [<CommonParameters>]    
    - Install-ContainerImage [-Name] <string[]> [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Force] [-Source <string>] [-WhatIf] [-Confirm] [<CommonParameters>]

### More examples
	#Finds the container image from an online gallery that match specified criteria. It can also search from other registered sources.
	# Find the latest version of all available container images
	Find-ContainerImage
	
	# Find thethe latest version of container image with the given name
	-Find-ContainerImage -Name ImageName
	
	# Find the latest version of all available container images that do not have version less than the given version
	-Find-ContainerImage -MinimumVersion Version
	
	# Find the latest version of all available container images that do not have version more than the given version
	-Find-ContainerImage -MaximumVersion Version
	
	# Find the latest version of all available container images that have the given version
	-Find-ContainerImage -RequiredVersion Version
	
	# Find the latest version of all versions of all available container images
	-Find-ContainerImage –AllVersions

	#Saves a container image without installing it. Save-ContainerImage cmdlet lets you save a container image locally without installing it. This lets you inspect the container image  before you install, helping to minimize the risks of malicious code or malware on your system.
	
	# Save the latest version of the given name to the directory that matches the wildcard Path
	-Save-ContainerImage -Name ImageName -Path C:\t*p\
	
	# Save the latest version of the given name to the directory that matches the LiteralPath
	-Save-ContainerImage -Name ImageName -LiteralPath C:\temp\
	
	# Save the latest version no less than the minimum version of the given name to the relative directory given by Path
	-Save -ContainerImage -Name ImageName -MinimumVersion Version -Path .\..\
	
	# Save the latest version no more than the maximum version of the given name to the directory that matches the LiteralPath
	-Save-ContainerImage -Name ImageName -MaximumVersion Version -LiteralPath C:\temp\
	
	# Save the given version of the given name to the directory that matches the Path
	-Save-ContainerImage -Name ImageName -RequiredVersion Version -Path C:\t*p\
	
	# Save the given version of the given name to the directory that matches the Path of the default Source
	-Save-ContainerImage -Name ImageName -RequiredVersion Version -Path C:\t*p\ -Source ContainerImageGallery
	
	# All results of the find will be saved in the given LiteralPath
	-Find-ContainerImage -Name ImageName | Save-ContainerImage -LiteralPath C:\temp\

	#Downloads the image from the cloud and installs them on the local computer. The Install-ContainerImage gets the container image that meets the specified cirteria from the cloud.  It saves the image locally and then installs it.
	
	# Installing the latest version of the given name to the local machine
	-Install-ContainerImage -Name ImageName
	
	# Installing the latest version of the given name from ContainerImageGallery to the local machine
	-Install-ContainerImage -Name ImageName -Source ContainerImageGallery
	
	# Installing the latest version greater the given version of the given name to the local machine
	-Install-ContainerImage -Name ImageName -MinimumVersion Version
	
	# Installing the latest version less than or equal to the given version of the given name to the local machine
	-Install-ContainerImage -Name ImageName -MaximumVersion Version
	
	# Installing the given version of the given name to the local machine
	-Install-ContainerImage -Name ImageName -RequiredVersion Version
	
	# Install all the results of find
	-Find-ContainerImage -Name ImageName | Install-ContainerImage

### Version
0.6.5.0

### Version History

#### 0.5.2
Initial public release for ContainerProvider

#### 0.5.3
Adding capacity to handle folders on share 

#### 0.6.4.0
#####Revamped the provider:
######1. Renamed to ContainerImage
######2. Abides by all OneGet Provider Rules
######3. Updated the parameter Destination to Path/LiteralPath
######4. Can handle folders on share
######5. Fixed the issue of downloading large installer on Nano and remoting via BITS
######6. This version needs the Windows Server 2016 Technical Preview 5 operating system, otherwise the commands will fail

### 0.6.4.1
Fixed the issue of loading System assemblies

### Dependencies
This module has no dependencies