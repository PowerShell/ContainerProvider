### Introduction
ContainerProvider is a Windows PowerShell module to find, save or install Containers.

### Version
0.5

### ContainerProvider cmdlets
    - Find-ContainerImage -Name ImageName

    - Find-ContainerImage -Name imagename
    - Find-ContainerImage -Version 1.2.3.5
    - Find-ContainerImage -Name imagename -Version 1.2.3.4
    - Save-ContainerImage -Name imagename -Destination C:\temp\ImageName.wim
    - Save-ContainerImage -Name imagename -Version 1.2.3.5 -Destination C:\temp\ImageName.wim
    - Install-ContainerImage -Name imagename
    - Install-ContainerImage -Name imagename -Version 1.2.3.5
