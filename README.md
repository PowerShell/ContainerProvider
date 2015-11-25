### Introduction
ContainerProvider is a Windows PowerShell module to find, save or install Containers.

### ContainerProvider cmdlets
	- Find-ContainerImage [-Name <String>] [-Version <Version>]
	- Save-ContainerImage [-Name <String>] [-Version <Version>] [-Destination <Path to file>]
	- Install-ContainerImage [-Name <String>] [-Version <Version>]

### Version
0.5.3

### Version History

#### 0.5.2
Initial public release fo ContainerProvider

#### 0.5.3
Added check to ensure there is enough space on the drive before saving

### Dependencies
This module has no dependencies