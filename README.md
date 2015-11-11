### Introduction
ContainerProvider is a Windows PowerShell module to find, save or install Containers.

### Version
0.5

### ContainerProvider cmdlets
    - Find-ContainerImage -Name ImageName
    - Find-ContainerImage -Version 1.2.3.5
    - Find-ContainerImage -Name ImageName -Version 1.2.3.4
    - Save-ContainerImage -Name ImageName -Destination C:\temp\ImageName.wim
    - Save-ContainerImage -Name ImageName -Version 1.2.3.5 -Destination C:\temp\ImageName.wim
    - Install-ContainerImage -Name ImageName
    - Install-ContainerImage -Name ImageName -Version 1.2.3.5