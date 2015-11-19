function Save-HTTPItem
{
    [CmdletBinding()]
    param(
       [Parameter(Mandatory=$true)]
       $Uri,
       [Parameter(Mandatory=$true)]
       $Destination
    )

    begin
    {
        $fullUri = [Uri]$Uri
        if (($fullUri.Scheme -ne 'http') -and ($fullUri.Scheme -ne 'https'))
        {
            throw "Uri: $uri is not supported. Only http or https schema are supported."
        }

        <# Assuming over-writing is approved at this point
        if (Test-Path $destination)
        {
            throw "File $destination exists"
        }
        #>
    }

    end
    {
        $headers = @{'x-ms-client-request-id'=$(hostname);'x-ms-version'='2015-02-21'}
        $prop = Invoke-HttpClient -FullUri $fullUri -Verbose -Headers $headers -Method Head -ea SilentlyContinue -ev ev
        if ($ev)
        {
            throw $ev
        }
        
        $cLength = $prop.Headers.ContentLength
        $sizePerCall = 4mb
        # TODO: This is not accurate but close
        $totalJobs = ($cLength/$sizePerCall) + 1
        $completedJobs = 0

        $mmpFile = [System.IO.MemoryMappedFiles.MemoryMappedFile]::CreateFromFile($destination, [System.IO.FileMode]::Create,
                (Split-Path -Leaf $destination), $cLength, [System.IO.MemoryMappedFiles.MemoryMappedFileAccess]::ReadWrite );
        try
        {
            $iss = [initialsessionstate]::CreateDefault()
            $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('Write-Verbose',[Microsoft.PowerShell.Commands.WriteVerboseCommand], $null))
            $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new('Wait-Debugger',[Microsoft.PowerShell.Commands.WaitDebuggerCommand], $null))
            $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new('Save-RSTBlobItem', (get-command Save-RSTBlobItem).Definition))
            $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new('Invoke-HTTPClient', (get-command Invoke-HTTPClient).Definition))
            #$iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new('Write-Log', (get-command Write-Log).Definition))
            $iss.LanguageMode = 'NoLanguage'
            $rsp = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool($iss)
            $null = $rsp.SetMinRunspaces(1)
            $null = $rsp.SetMaxRunspaces(10)
            $rsp.Open()

            Write-Progress -Activity "Downloading from $fulluri" -status 'Status' -PercentComplete 0

            $pipelines = [System.Collections.ObjectModel.Collection[powershell]]::new()
            $asyncResults = [System.Collections.ObjectModel.Collection[System.IAsyncResult]]::new()
            $waitHandles = @()
            $start = 0;
            $end = 0;
            do
            {
                # [System.Threading.WaitHandle]::WaitAny can accept only 64 wait handles
                for( ;($start -lt $cLength) -and ($asyncResults.Count -lt 63); $start = $end + 1)
                {
                    $end = $start + $sizePerCall - 1;
                    if ($end -ge $cLength) 
                    { 
                        $end = $cLength - 1
                    }
                    $ps = [powershell]::Create().AddCommand('Save-RSTBlobItem').AddParameter('fullUri',$fullUri).AddParameter('mmpFile',$mmpFile).AddParameter('byteStart',$start).AddParameter('byteEnd',$end)
                    $ps.RunspacePool = $rsp
                    $pipelines.Add($ps)

                    $iasyncResult = $ps.BeginInvoke()
                    $asyncResults.Add($iasyncResult)
                }
      
                $waitHandles = @($asyncResults | % AsyncWaitHandle)

                $index = [System.Threading.WaitHandle]::WaitAny($waitHandles, -1)
                $completedJobs++
                $ps = $pipelines[$index]
                $ps.EndInvoke($asyncResults[$index])
                $ps.Streams.Error
                $ps.Streams.Verbose
                $ps.dispose()
                $null = $pipelines.Remove($pipelines[$index])
                $null = $asyncResults.Remove($asyncResults[$index])

                Write-Progress -Activity "Downloading from $fulluri" -status 'Status' -PercentComplete ((($completedJobs)/$totalJobs)*100)
            
            } while(($start -lt $cLength) -or ($asyncResults.Count -gt 0))
            Write-Progress -Activity "Downloading from $fulluri" -Status 'Status' -Completed
        }
        finally
        {
            $rsp.Dispose()
            $mmpFile.Dispose()
        }
    }
}

function Save-RSTBlobItem
{
    param(
        $fullUri = $(throw 'fullUri cannot be null.'),
        $mmpFile = $(throw 'mmpFile cannot be null.'),
        $byteStart,
        $byteEnd        
    )
        
    $length = $byteEnd - $byteStart + 1
    if ($length -le 0)
    {
        throw 'byteEnd is greaterthan byteStart'
    }

    $sizePerIteration = 4mb
    

    $mmvs = $mmpFile.CreateViewStream($byteStart, $length, 'Write')
    try
    {
      for($start = $byteStart; $start -le $byteEnd; $start = $end + 1)
      {
            $end = $start + $sizePerIteration - 1;
            if ($end -ge $byteEnd) 
            { 
                $end = $byteEnd
            }

            $headers = @{
                'x-ms-range' = "bytes=$start-$End";
                'x-ms-version'='2015-02-21';
                'x-ms-client-request-id'='ContainerImageProvider'
            }  

            #$data = Invoke-WebRequest $fullUri -Headers $headers -Method GET
            #$data.RawContentStream.CopyTo($mmvs)

            $streamContent = Invoke-HTTPClient -FullUri $fullUri -Headers $headers -httpMethod Get -retryCount 4
            $copyTask = $streamContent.CopyToAsync($mmvs)
            $null = $copyTask.AsyncWaitHandle.WaitOne()
            $copyTask.Dispose()
            $streamContent.Dispose()
      }
    }
    catch
    {
       Write-Error "$_"
    }
    finally
    {
        $mmvs.Close()
    }
}

function Invoke-HTTPClient
{
   param(
      [Uri] $FullUri,
      [Hashtable] $Headers,
      [ValidateSet('Get','Head')]
      [string] $httpMethod,
      [int] $retryCount = 0
   )

   $poshExtensionExist = ([psobject].Assembly.GetType('Microsoft.PowerShell.CoreCLR.AssemblyExtensions'))
   if ($poshExtensionExist)
   {
        # Nano case
        $snhAssemblyPath = join-path $env:windir "System32\DotNetCore\v1.0\System.Net.Http.dll"
        $null = [Microsoft.PowerShell.CoreCLR.AssemblyExtensions]::LoadFrom($snhAssemblyPath )
   }
   else
   {
        # Non-Nano case
        Add-Type -AssemblyName System.Net.Http
   }

   do
   {
        $httpClient = [System.Net.Http.HttpClient]::new()
        foreach($headerKey in $Headers.Keys)
        {
            $httpClient.DefaultRequestHeaders.Add($headerKey, $Headers[$headerKey])
        }
  
        $HttpCompletionOption = 'ResponseContentRead'
        if ($httpMethod -eq 'Get')
        {   
            $httpRequestMessage = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $fullUri)
        }
        else
        {
            $httpRequestMessage = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head, $fullUri)
            $HttpCompletionOption = 'ResponseHeadersRead'
        }  
   
        $result = $httpClient.SendAsync($httpRequestMessage, $HttpCompletionOption)
        $null = $result.AsyncWaitHandle.WaitOne()

        if ($result.Result.IsSuccessStatusCode)
        {
            break;
        }
        $retryCount--;
        $msg = 'RetryCount: {0}, Http.GetAsync did not return successful status code. Status Code: {1}, {2}' -f `
                    $retryCount, $result.Result.StatusCode, $result.Result.ReasonPhrase 
        $msg = $msg + ('Result Reason Phrase: {0}' -f $result.Result.ReasonPhrase)
   } while($retryCount -gt 0)

   if (-not $result.Result.IsSuccessStatusCode)
   {
       $msg = 'Http.GetAsync did not return successful status code. Status Code: {0}, {1}' -f `
                    $result.Result.StatusCode, $result.Result.ReasonPhrase    
       throw $msg
   }
   return $result.Result.Content
}
