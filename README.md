### Introduction

ContainerProvider is a Windows PowerShell module to find, save or install Windows Server Containers.  It also implements a OneGet/PackageManagement provider.

### Examples: ContainerProvider cmdlet

 # To Discover Container Images use the following cmdlets
 Find-ContainerImage -Name imagename  
 Find-ContainerImage -Version 1.2.3.5  
 Find-ContainerImage -Name imagename -Version 1.2.3.4  
 
 # To Save Container images use the following cmdlets
 Save-ContainerImage -Name imagename -Destination C:\temp\ImageName.wim  
 Save-ContainerImage -Name imagename -Version 1.2.3.5 -Destination C:\temp\ImageName.wim  
 
 # To Install container images use the following cmdlets
 Install-ContainerImage -Name imagename  
 Install-ContainerImage -Name imagename -Version 1.2.3.5  

