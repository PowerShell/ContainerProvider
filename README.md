### Introduction
ContainerImage is a Windows PowerShell module to find, save or install Containers.

### ContainerImage cmdlets
	- Find-ContainerImage [[-Name] <string[]>] [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-AllVersions] [-source <string>] [<CommonParameters>]
	- Save-ContainerImage [-Name] <string[]> -Path <string> [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Force] [-source <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
	- Save-ContainerImage [-Name] <string[]> -LiteralPath <string> [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Force] [-source <string>] [-WhatIf] [-Confirm]  [<CommonParameters>]
	- Install-ContainerImage [-Force] [-Source <string>] [-WhatIf] [-Confirm]  [<CommonParameters>]    
    - Install-ContainerImage [-Name] <string[]> [-MinimumVersion <version>] [-MaximumVersion <version>] [-RequiredVersion <version>] [-Force] [-Source <string>] [-WhatIf] [-Confirm] [<CommonParameters>]

### Version
0.6.2.0

### Version History

#### 0.5.2
Initial public release for ContainerProvider

#### 0.5.3
Adding capacity to handle folders on share 

#### 0.6.2.0
Revamped the provider:
	1. Renamed to ContainerImage
	2. Abides by all OneGet Provider Rules
	3. Updated the parameter Destination to Path/LiteralPath
	4. Can handle folders on share
	5. Fixed the issue of downloading large installer on Nano and remoting via BITS

### Dependencies
This module has no dependencies
