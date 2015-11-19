### Introduction

ContainerProvider is a Windows PowerShell module to find, save or install Windows Server Containers.  It also implements a OneGet/PackageManagement provider.

### Examples: ContainerProvider cmdlet

PS C:\> Find-ContainerImage

Name                 Version                 Description                        
----                 -------                 -----------                        
NanoServer           10.0.10586.0            Container OS Image of Windows Se...
WindowsServerCore    10.0.10586.0            Container OS Image of Windows Se...



PS C:\> Save-ContainerImage NanoServer -Destination C:\temp\nano.wim
