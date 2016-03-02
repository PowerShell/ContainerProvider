$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.ps1", ".psm1")
. "$here\..\$sut"

Describe “Find-ContainerImage" {
    
    BeforeAll {
        #Find-Module ContainerProvider -Repository PSGallery | Install-Module -Force
        Import-Module ContainerProvider
        Import-PackageProvider ContainerProvider
    }

    AfterAll {
        "Finished running the Find-ContainerImage tests"
    }

    It "Finds ContainerImage Stand-Alone Cloud" {

        $commands = @()
        $commands += "Find-ContainerImage -Source ContainerImageGallery"
        $commands += "Find-ContainerImage -version 10.0.10586.0"
        
        foreach($command in $commands)
        {
            "Running Find ContainerImage for command: $command"
            $results = Invoke-Expression $command

            $results.count -eq 2 | should be $true

            $resultFirst = $results[0]
            $resultSecond = $results[1]

            $source = "ContainerImageGallery"
            $version = "10.0.10586.0"
            $nanoName = "NanoServer"
            $serverName = "WindowsServerCore"
            $nanoDesc = "Container OS Image of Windows Server 2016 Technical Preview 4 : Nano Server Installation"
            $serverDesc = "Container OS Image of Windows Server 2016 Technical Preview : Windows Server Core Installation"
            $nanoSasT = "https://pshctnoncdn.blob.core.windows.net/pshctcontainer/CBaseOs_th2_release_10586.0.151029-1700_amd64fre_NanoServer_en-us.wim?sv=2015-02-21&sr=b&sig=AjH0HKS%2BEBEbiEcFheUE1hE7MnOmizXgW6JB0PVTQJk%3D&st=2015-11-17T22%3A56%3A53Z&se=2016-11-17T22%3A56%3A53Z&sp=r"
            $serverSasT = "https://pshctnoncdn.blob.core.windows.net/pshctcontainer/CBaseOs_th2_release_10586.0.151029-1700_amd64fre_ServerDatacenterCore_en-us.wim?sv=2015-02-21&sr=b&sig=rLNvGpycEElTr52U6EwrMmnzSRVbsCSIEuO%2B7oa8HYI%3D&st=2015-11-17T22%3A57%3A58Z&se=2016-11-17T22%3A57%3A58Z&sp=r"

            $resultFirst.Name | should be $nanoName
            $resultFirst.description | should be $nanoDesc
            $resultFirst.sasToken | should be $nanoSasT
            $resultFirst.source | should be $source
            $resultFirst.version | should be $version

            $resultSecond.Name | should be $serverName
            $resultSecond.description | should be $serverDesc
            $resultSecond.sasToken | should be $serverSasT
            $resultSecond.source | should be $source
            $resultSecond.version | should be $version
        }
    }

    It "Finds ContainerImage One-Get Cloud" {

        $commands = @()
        $commands += "Find-Package -ProviderName ContainerProvider -Source ContainerImageGallery"
        
        foreach($command in $commands)
        {
            "Running Find ContainerImage for command: $command"
            $results = Invoke-Expression $command

            $results.count -eq 2 | should be $true

            $resultFirst = $results[0]
            $resultSecond = $results[1]

            $source = "ContainerImageGallery"
            $version = "10.0.10586.0"
            $nanoName = "NanoServer"
            $nanoDesc = "Container OS Image of Windows Server 2016 Technical Preview 4 : Nano Server Installation"
            $serverName = "WindowsServerCore"
            $serverDesc = "Container OS Image of Windows Server 2016 Technical Preview : Windows Server Core Installation"
            
            $resultFirst.Name | should be $nanoName
            $resultFirst.Summary | should be $nanoDesc
            $resultFirst.source | should be $source
            $resultFirst.version | should be $version

            $resultSecond.Name | should be $serverName
            $resultSecond.Summary | should be $serverDesc
            $resultSecond.source | should be $source
            $resultSecond.version | should be $version
        }
    }

    It "Find ContainerImages Stand-Alone UNCPath" {
        $baseFolder = "\\winbuilds\release\RS1_ONECORE_CONTAINER_HYP"        
        $guid = [guid]::NewGuid()
        $badSource = "internal_bad_$guid"
        $null = Register-PackageSource -name  $badSource `
                                             -ProviderName ContainerProvider `
                                             -Location $baseFolder        
        
        $results = Find-ContainerImage -Source $badSource

        $results.count -eq 0 | should be $true        

        $null = Unregister-PackageSource -name $badSource `
                                            -ProviderName ContainerProvider
    }

    It "Find ContainerImages Stand-Alone UNCPath" {
        $baseFolder = "\\winbuilds\release\RS1_ONECORE_CONTAINER_HYP"
        $children = Get-ChildItem -Directory -Path $baseFolder | sort -property LastWriteTime -Descending
        $latestBuild = $children[2]
        $secondaryPath = "amd64fre\ContainerBaseOsPkgs\cbaseospkg_nanoserver_en-us"
        $fullPath = Join-Path (Join-Path $baseFolder $latestBuild) $secondaryPath
        $guid = [guid]::NewGuid()
        $sourceInternal = "internal_$guid"
        $null = Register-PackageSource -name  $sourceInternal `
                                             -ProviderName ContainerProvider `
                                             -Location $fullPath

        $nanoName = "NanoServer"
        $file = Get-ChildItem -File -Path $fullPath -Filter "*.wim"
        $fileWithPath = Join-Path $fullPath $file
        $containerImageInfo = Get-WindowsImage -ImagePath $fileWithPath -Index 1
        $containerImageVersion = $containerImageInfo.Version
        $description = "Nano " + $containerImageVersion
        
        $results = Find-ContainerImage -Source $sourceInternal

        $results.count -eq 1 | should be $true
        $resultFirst = $results[0]            
        $resultFirst.Name -eq $nanoName | should be $true
        $resultFirst.version -eq $containerImageVersion | should be $true
        $resultFirst.Source -eq $sourceInternal | should be $true
        $resultFirst.Description -eq $description | should be $true

        $null = Unregister-PackageSource -name $sourceInternal `
                                            -ProviderName ContainerProvider
    }

    It "Find ContainerImages One-Get UNCPath" {
        $baseFolder = "\\winbuilds\release\RS1_ONECORE_CONTAINER_HYP"
        $children = Get-ChildItem -Directory -Path $baseFolder | sort -property LastWriteTime -Descending
        $latestBuild = $children[2]
        $secondaryPath = "amd64fre\ContainerBaseOsPkgs\cbaseospkg_nanoserver_en-us"
        $fullPath = Join-Path (Join-Path $baseFolder $latestBuild) $secondaryPath
        $guid = [guid]::NewGuid()
        $sourceInternal = "internal_$guid"
        $null = Register-PackageSource -name  $sourceInternal `
                                             -ProviderName ContainerProvider `
                                             -Location $fullPath

        $nanoName = "NanoServer"
        $file = Get-ChildItem -File -Path $fullPath -Filter "*.wim"
        $fileWithPath = Join-Path $fullPath $file
        $containerImageInfo = Get-WindowsImage -ImagePath $fileWithPath -Index 1
        $containerImageVersion = $containerImageInfo.Version
        $description = "Nano " + $containerImageVersion
        
        $results = Find-Package -ProviderName ContainerProvider -Source $sourceInternal

        $results.count -eq 1 | should be $true
        $resultFirst = $results[0]            
        $resultFirst.Name -eq $nanoName | should be $true
        $resultFirst.version -eq $containerImageVersion | should be $true
        $resultFirst.Source -eq $sourceInternal | should be $true
        $resultFirst.Summary -eq $description | should be $true

        $null = Unregister-PackageSource -name $sourceInternal `
                                            -ProviderName ContainerProvider
    }
}

Describe “Save-ContainerImage" {
    BeforeAll{
        
        $savePath = "C:\temp\ContainerProvider"
        if(-not (Test-Path $savePath))
        {
            "Creating the folder: $savePath"
            $null = mkdir $savePath
        }
    }

    AfterAll {
        
        "Removing the folder: $savePath"
        $null = rmdir $savePath -Force
    }

    It "Save ContainerImages from PSGallery" {

        $pathNano = Join-Path $savePath "NanoServer.wim"
        
        # Save the container image
        $resultNano = Save-ContainerImage -Name NanoServer -Destination $pathNano

        # Check if the container image is downloaded
        (Test-Path $pathNano) | should be $true
        
        # Remove the container image
        "Removing existing item: $pathNano"
        $null = Remove-Item $pathNano -Force

        $pathServer = Join-Path $savePath "WindowsServer.wim"
        
        # Save the container image
        $resultServer = Save-ContainerImage -Name WindowsServerCore -Destination $pathServer
        (Test-Path $pathServer) | should be $true

        # Remove the container image
        "Removing existing item: $pathServer"
        $null = Remove-Item $pathServer -Force
    }

    It "Save ContainerImage from UNC Path" {
        $baseFolder = "\\winbuilds\release\RS1_ONECORE_CONTAINER_HYP"
        $children = Get-ChildItem -Directory -Path $baseFolder | sort -property LastWriteTime -Descending
        $latestBuild = $children[2]
        $secondaryPath = "amd64fre\ContainerBaseOsPkgs\cbaseospkg_nanoserver_en-us"
        $fullPath = Join-Path (Join-Path $baseFolder $latestBuild) $secondaryPath
        $guid = [guid]::NewGuid()
        $sourceInternal = "internal_$guid"
        $null = Register-PackageSource -name  $sourceInternal `
                                             -ProviderName ContainerProvider `
                                             -Location $fullPath

        $nanoName = "NanoServer"
        $file = Get-ChildItem -File -Path $fullPath -Filter "*.wim"
        $fileWithPath = Join-Path $fullPath $file
        $containerImageInfo = Get-WindowsImage -ImagePath $fileWithPath -Index 1
        $containerImageVersion = $containerImageInfo.Version
        $description = "Nano " + $containerImageVersion

        $fileName = "nanoserver_" + $guid + ".wim"
        $saveFile = Join-Path $savePath $fileName

        $results = Save-ContainerImage -name NanoServer -Destination $saveFile -Source $sourceInternal

        (Test-Path $saveFile) | should be $True

        $imageInfo = Get-WindowsImage -ImagePath $saveFile -Index 1
        $version = $imageInfo.Version

        $version | should be $containerImageVersion
    }
}

Describe “Helper Function Tests" {

    BeforeAll {
        Import-Module ContainerProvider
    }

    InModuleScope ContainerProvider {

        # Get-Sources
        It "Get-Sources Test" {
            $listOfSources = Get-Sources

            $listOfSources.Count -gt 0 | should be $true

            $fwdLink = "http://go.microsoft.com/fwlink/?LinkID=627586&clcid=0x409"
            $queryKey = "82E9CC3E0342EA5C9B95ED909FC8E039"
            $indexName = "pshct-pub-srch-index"
            $pkgSourceName = "ContainerImageGallery"
            
            foreach($source in $listOfSources)
            {
                if($source.PackageSourceName -eq $pkgSourceName)
                {
                    $source.Location -eq $fwdLink | should be $true
                    $source.QueryKey -eq $queryKey | should be $true
                    $source.IndexName -eq $indexName | should be $true
                    $source.PackageSourceName -eq $pkgSourceName | should be $true
                }
            }
        }

        # Find on Azure cloud
        It "Find-Azure test" {
            
            $name = ""
            $version = ""
            $fwdLink = "http://go.microsoft.com/fwlink/?LinkID=627586&clcid=0x409"
            $queryKey = "82E9CC3E0342EA5C9B95ED909FC8E039"
            $indexName = "pshct-pub-srch-index"
            $pkgSourceName = "ContainerImageGallery"

            $results = Find-Azure -Name $name `
                                    -Version $version `
                                    -fwdLink $fwdLink `
                                    -indexName $indexName `
                                    -queryKey $queryKey `
                                    -packageSourceName $pkgSourceName

            $results.count -eq 2 | should be $true

            $resultFirst = $results[0]
            $resultSecond = $results[1]

            $source = "ContainerImageGallery"
            $version = "10.0.10586.0"

            $nanoName = "NanoServer"
            $nanoDesc = "Container OS Image of Windows Server 2016 Technical Preview 4 : Nano Server Installation"
            $nanoSasT = "https://pshctnoncdn.blob.core.windows.net/pshctcontainer/CBaseOs_th2_release_10586.0.151029-1700_amd64fre_NanoServer_en-us.wim?sv=2015-02-21&sr=b&sig=AjH0HKS%2BEBEbiEcFheUE1hE7MnOmizXgW6JB0PVTQJk%3D&st=2015-11-17T22%3A56%3A53Z&se=2016-11-17T22%3A56%3A53Z&sp=r"

            $serverName = "WindowsServerCore"
            $serverDesc = "Container OS Image of Windows Server 2016 Technical Preview : Windows Server Core Installation"
            $serverSasT = "https://pshctnoncdn.blob.core.windows.net/pshctcontainer/CBaseOs_th2_release_10586.0.151029-1700_amd64fre_ServerDatacenterCore_en-us.wim?sv=2015-02-21&sr=b&sig=rLNvGpycEElTr52U6EwrMmnzSRVbsCSIEuO%2B7oa8HYI%3D&st=2015-11-17T22%3A57%3A58Z&se=2016-11-17T22%3A57%3A58Z&sp=r"
        
            $resultFirst.Name -eq $nanoName | should be $true
            $resultFirst.description -eq $nanoDesc | should be $true
            $resultFirst.sasToken -eq $nanoSasT | should be $true
            $resultFirst.source -eq $source | should be $true
            $resultFirst.version -eq $version | should be $true
        
            $resultSecond.Name -eq $serverName | should be $true
            $resultSecond.description -eq $serverDesc | should be $true
            $resultSecond.sasToken -eq $serverSasT | should be $true
            $resultSecond.source -eq $source | should be $true
            $resultSecond.version -eq $version | should be $true
        }

        # Find wim in the UNC path
        It "Find-UNCPath Success" {

            $baseFolder = "\\winbuilds\release\RS1_ONECORE_CONTAINER_HYP"
            $children = Get-ChildItem -Directory -Path $baseFolder | sort -property LastWriteTime -Descending
            $latestBuild = $children[2]
            $secondaryPath = "amd64fre\ContainerBaseOsPkgs\cbaseospkg_nanoserver_en-us"
            $fullPath = Join-Path (Join-Path $baseFolder $latestBuild) $secondaryPath
            $sourceInternal = "internal"
            
            $results = Find-UNCPath -localPath $fullPath `
                                        -packageSourceName $sourceInternal

            $results.count -eq 1 | should be $true
            $resultFirst = $results[0]
            $nanoName = "NanoServer"
            $file = Get-ChildItem -File -Path $fullPath -Filter "*.wim"
            $fileWithPath = Join-Path $fullPath $file
            $version = get-Version $fileWithPath
            $description = "Nano " + $version
            
            $resultFirst.Name -eq $nanoName | should be $true
            $resultFirst.version -eq $version | should be $true
            $resultFirst.Source -eq $sourceInternal | should be $true
            $resultFirst.Description -eq $description | should be $true
        }

        # Save network file
        It "Save network File" {
            $uncLocation = "\\scratch2\scratch\jayshah\PesterTest"
            $networkFile = Join-Path $uncLocation "testFile.txt"
            $savePath = "C:\temp\ContainerProvider"
            if(-not (Test-Path $savePath))
            {
                "Creating the folder: $savePath"
                $null = mkdir $savePath
            }

            $null = Save-File -downloadURL $uncLocation `
                                -destination $networkFile

            (Test-Path $networkFile) | should be $true

            $null = Remove-Item $networkFile -Force
            $null = rmdir $savePath -Force
        }

        # Save file from Azure blob store
        It "Save cloud File" {
            $sasToken = "https://pshctnoncdn.blob.core.windows.net/pshctcontainer/CBaseOs_th2_release_10586.0.151029-1700_amd64fre_NanoServer_en-us.wim?sv=2015-02-21&sr=b&sig=AjH0HKS%2BEBEbiEcFheUE1hE7MnOmizXgW6JB0PVTQJk%3D&st=2015-11-17T22%3A56%3A53Z&se=2016-11-17T22%3A56%3A53Z&sp=r"
            $savePath = "C:\temp\ContainerProvider"
            if(-not (Test-Path $savePath))
            {
                "Creating the folder: $savePath"
                $null = mkdir $savePath
            }

            $cloudFile = Join-Path $savePath "azureFile.wim"
            $null = Save-File -downloadURL $sasToken `
                                -destination $cloudFile

            (Test-Path $cloudFile) | should be $true

            $null = Remove-Item $cloudFile -Force
            $null = rmdir $savePath  -Force
        }

        # Resolve FWD Link
        It "FWD Link test" {

            $fwdLink = "http://go.microsoft.com/fwlink/?LinkID=627586&clcid=0x409"
            $rslvdLink = "https://pshct-srch-pub.search.windows.net/"
            
            $resolvedLink = Resolve-FwdLink $fwdLink

            $rslvdLink | should be $resolvedLink
        }

        # Get the version
        It "Get the version" {
            $baseFolder = "\\winbuilds\release\RS1_ONECORE_CONTAINER_HYP"
            $children = Get-ChildItem -Directory -Path $baseFolder | sort -property LastWriteTime -Descending
            $latestBuild = $children[2]
            $secondaryPath = "amd64fre\ContainerBaseOsPkgs\cbaseospkg_nanoserver_en-us"
            $fullPath = Join-Path (Join-Path $baseFolder $latestBuild) $secondaryPath            
            $file = Get-ChildItem -File -Path $fullPath -Filter "*.wim"
            $fileWithPath = Join-Path $fullPath $file
            $containerImageInfo = Get-WindowsImage -ImagePath $fileWithPath -Index 1
            $containerImageVersion = $containerImageInfo.Version
            $version = get-Version $fileWithPath

            $resultVersion = get-Version $fileWithPath

            $resultVersion -eq $containerImageVersion | should be $true
        }
    }
}