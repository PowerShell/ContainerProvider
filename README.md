### Introduction
ContainerImage is a <a href="https://oneget.org/">PackageManagement</a> provider to find, save or install Container Images.

### ContainerImage cmdlets
	- Find-ContainerImage [[-Name] <string[]>] [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-AllVersions] [-source <string>] [<CommonParameters>]
	- Save-ContainerImage [-Name] <string[]> -Path <string> [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Force] [-source <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
	- Save-ContainerImage [-Name] <string[]> -LiteralPath <string> [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Force] [-source <string>] [-WhatIf] [-Confirm]  [<CommonParameters>]
	- Install-ContainerImage [-Force] [-Source <string>] [-WhatIf] [-Confirm]  [<CommonParameters>]    
    - Install-ContainerImage [-Name] <string[]> [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Force] [-Source <string>] [-WhatIf] [-Confirm] [<CommonParameters>]

### Examples
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
	-Install -ContainerImage -Name ImageName
	
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
0.6.2.0

### Version History

#### 0.5.2
Initial public release for ContainerProvider

#### 0.5.3
Adding capacity to handle folders on share 

#### 0.6.2.0
#####Revamped the provider:
######1. Renamed to ContainerImage
######2. Abides by all OneGet Provider Rules
######3. Updated the parameter Destination to Path/LiteralPath
######4. Can handle folders on share
######5. Fixed the issue of downloading large installer on Nano and remoting via BITS

### Dependencies
This module has no dependencies
