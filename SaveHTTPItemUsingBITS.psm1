function Save-HTTPItemUsingBitsTransfer
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
    }
    
    end
    {
        $jstate = $null
        [bool] $isTransferCompleted = $false
        try
        {
            $mycurrentPath = $script:MyInvocation.MyCommand.Path
            $myCurrentDirectory = Split-Path $mycurrentPath
            $bitsCommandPath = join-path $myCurrentDirectory "BitsOnNano.exe"
            $jobNameTemp = "SH{0}" -f (get-date).Ticks
            $output = & $bitsCommandPath -Start-Transfer  -DisplayName $jobNameTemp -Source $Uri -Destination $Destination
            $le = $lastexitcode
            [Console]::CursorTop = [Console]::CursorTop + 1
            $ChagedTop = [Console]::CursorTop           

            do
            {
                $jname,$jid,$jstate,$jbytesTransferred,$jbytesTotal,$null = $output -split ":"
                
                if ( (@("BG_JOB_STATE_ERROR", "BG_JOB_STATE_TRANSIENT_ERROR", "BG_JOB_STATE_CANCELLED") -contains $jstate) -or ($le))
                {
                    & $bitsCommandPath -Stop-Transfer -ID $jid | Out-Null

                     throw "Save-HTTPItem: Bits Transfer failed. Job State: $jstate ExitCode = $le"
                }
                
                if (@("BG_JOB_STATE_TRANSFERRING") -contains $jstate)
                {
                    [Console]::CursorTop = $ChagedTop
                    [Console]::CursorLeft = 0
                    [Console]::WriteLine("Downloaded $jbytesTransferred mb of $jbytesTotal mb")
                }
                elseif (@("BG_JOB_STATE_TRANSFERRED") -contains $jstate)
                {
                    & $bitsCommandPath -Remove-Transfer -ID $jid | Out-Null
                    $isTransferCompleted = $true
                    break;
                }
                elseif (@("BG_JOB_STATE_QUEUED") -contains $jstate)
                {
                    #Write-Progress -Activity "Downloading from $Uri" -Status "Queued"
                }
                elseif (@("BG_JOB_STATE_CONNECTING") -contains $jstate)
                {
                    #Write-Progress -Activity "Downloading from $Uri" -Status "Connecting"
                }
                elseif (@("BG_JOB_STATE_ACKNOWLEDGED") -contains $jstate)
                {
                    #Write-Progress -Activity "Downloading from $Uri" -Status "Acknowledged"
                }

                Start-Sleep -Seconds 1
                $output = & $bitsCommandPath -Get-TransferStatus -ID $jid
                $le = $lastExitCode
            }while($true);
        }
        finally
        {
            #"Calling finally: jstate:$jstate isTC:$isTransferCompleted"
            #Write-Progress -Activity "Downloading from $Uri" -Status "Status" -Completed
            [Console]::CursorTop = $ChagedTop
            [Console]::CursorLeft = 0
            [Console]::WriteLine([String]::new(" ", [Console]::WindowWidth))

            if ((-not $jstate)  -and (-not $isTransferCompleted))
            {
               "CleanUp:"
               & $bitsCommandPath -Stop-Transfer -ID $jid | Out-Null
            }
        }        
    }
}
# SIG # Begin signature block
# MIIargYJKoZIhvcNAQcCoIIanzCCGpsCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU3PYdSLgc+r5nRa4xooNY1YYI
# gaGgghWBMIIEwjCCA6qgAwIBAgITMwAAAJJMoq9VJwgudQAAAAAAkjANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTUxMDA3MTgxNDE0
# WhcNMTcwMTA3MTgxNDE0WjCBsjELMAkGA1UEBhMCVVMxEjAQBgNVBAgTCVdhc2lu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMQ0wCwYDVQQLEwRNT1BSMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046
# N0QyRS0zNzgyLUIwRjcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNl
# cnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC6WVT9G7wUxF8u
# /fnFTnid7MCYX4X58613PUnaf2uYaz291cpmbxNeEsx+HZ8xrgjCHkMC3U9rTUfl
# oyhWqlW3ZdZQdn97Qa++X7wXa/ybE8FeY0Qphe8K0w9hbhxRjbII4fInEEkM4GAd
# HLqPqQw+U+Ul/gAC8U64SnklxtsjxN2faP98po9YqDYGH/IGaej0Y9ojGA2aEpVh
# J6n3TezIbXNZDBZW1ODKX1W0OmKPNvTdGqFYAHCr6osCrVLyg4ROozoI9GnsvjC7
# f9ACbPJf6Xy1B2v0teYREkUmpqc+OC/rZpApjgtL2Y5ymgeuihuSUj/XaKNtDa0Z
# ERONWgyLAgMBAAGjggEJMIIBBTAdBgNVHQ4EFgQUBsPfWqqHee6gVxN8Wohmb0CT
# pgMwHwYDVR0jBBgwFoAUIzT42VJGcArtQPt2+7MrsMM1sw8wVAYDVR0fBE0wSzBJ
# oEegRYZDaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljcm9zb2Z0VGltZVN0YW1wUENBLmNybDBYBggrBgEFBQcBAQRMMEowSAYIKwYB
# BQUHMAKGPGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0VGltZVN0YW1wUENBLmNydDATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG
# 9w0BAQUFAAOCAQEAjgD2Z96da+Ze+YXIxGUX2pvvvX2etiR572Kwk6j6aXOFJrbB
# FaNelpipwJCRAY/V9qLIqUh+KfQFBKQYlRBf50WrCcXz+sx0BxyG597HjjGCmL4o
# Y0j/F0KATLMw60EcOh2I1hotO1a1W5fHB661OxD+T5KC6D9JN9TTP8vxap080i/V
# uNKyr2QubnfuOvs7jTjDJP5l5ZUEAFcxuliihARHhKnyoWxWcvje/fI463+pmRhF
# /nBuA3jTiCC5DWI3vST9I0l/BwrVDVMwvvnn5xf0vHb1U3TrJVeo2VRpHsqsoCA0
# 35Vuya6u01jEDkKhrZHuuMnxTAgCVuIFeXh9xDCCBOwwggPUoAMCAQICEzMAAAEK
# LHmu13l7pqwAAQAAAQowDQYJKoZIhvcNAQEFBQAweTELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEjMCEGA1UEAxMaTWljcm9zb2Z0IENvZGUgU2ln
# bmluZyBQQ0EwHhcNMTUwNjA0MTc0MjQ1WhcNMTYwOTA0MTc0MjQ1WjCBgzELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjENMAsGA1UECxMETU9QUjEe
# MBwGA1UEAxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAkvxvNrvhA7ko1kbRomG6pUb7YxY+LvlH0sfs7ceZsSZR
# db3azA8GFBGkbBmewF9NVInkTVDYjc2hYaV3E5ocp+0NdPenVnnoKPdT0rF6Y+D1
# lJe37NlH+Gw98yWIs7wKxQSnjnyFSHYcYUaqGcR6YovBwjWq+1hvxWMLk0kwgRt7
# 3398T7RHbV94HK+295YTUu+50U055XPeSE48FKqXDTnMi1HhXNE78I5n6jBgqU1a
# nUO92yO6wA/XSxCdnE3wUaKEquScpz3Wo+8KGEio+rFOpZgOS7/wFPMAyLBI1lv+
# ONeJES0FukMCTyIAliWtfTVuhGirIBg4KP4cohCxpQIDAQABo4IBYDCCAVwwEwYD
# VR0lBAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYEFIn+CjHqJs3mbceRkbmUjKIYYTc0
# MFEGA1UdEQRKMEikRjBEMQ0wCwYDVQQLEwRNT1BSMTMwMQYDVQQFEyozMTU5NSsw
# NDA3OTM1MC0xNmZhLTRjNjAtYjZiZi05ZDJiMWNkMDU5ODQwHwYDVR0jBBgwFoAU
# yxHoytK0FlgByTcuMxYWuUyaCh8wVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljQ29kU2lnUENBXzA4
# LTMxLTIwMTAuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNDb2RTaWdQQ0FfMDgtMzEt
# MjAxMC5jcnQwDQYJKoZIhvcNAQEFBQADggEBAKaoU5HfOwH+YV0GWutm8AzY99mE
# 0wBRDhDRpNEXKOeMMzgr2EPGA4t16zOS9KniZ/0C26UdTkNFXRtJ4+BPFvB+j/CI
# EcqCraT7pqlf9ZdgyHvEv3ybae0fgsHxzY54S2L11w0c11MS1pZS7zW9GY6gQJOh
# CqUtFpzCRnQI69v02KVJNlQSEVUDs3sW+0f++2j8wEVc4j8SeTOi74LF3kAZB+4V
# xQqbWQVBqdCXnoGeA1v8SuMaLgWsUEcvjPp52B4g+AX7KWsYFPpyBLcLp5pk7BFd
# T0VJjSkaLfvQtglTXzSU4BbEuepzNehX7+HrFsMYxwazO89hhOK2RImUo4YwggW8
# MIIDpKADAgECAgphMyYaAAAAAAAxMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJ
# k/IsZAEZFgNjb20xGTAXBgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMT
# JE1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0xMDA4MzEy
# MjE5MzJaFw0yMDA4MzEyMjI5MzJaMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENB
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsnJZXBkwZL8dmmAgIEKZ
# dlNsPhvWb8zL8epr/pcWEODfOnSDGrcvoDLs/97CQk4j1XIA2zVXConKriBJ9PBo
# rE1LjaW9eUtxm0cH2v0l3511iM+qc0R/14Hb873yNqTJXEXcr6094CholxqnpXJz
# VvEXlOT9NZRyoNZ2Xx53RYOFOBbQc1sFumdSjaWyaS/aGQv+knQp4nYvVN0UMFn4
# 0o1i/cvJX0YxULknE+RAMM9yKRAoIsc3Tj2gMj2QzaE4BoVcTlaCKCoFMrdL109j
# 59ItYvFFPeesCAD2RqGe0VuMJlPoeqpK8kbPNzw4nrR3XKUXno3LEY9WPMGsCV8D
# 0wIDAQABo4IBXjCCAVowDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUyxHoytK0
# FlgByTcuMxYWuUyaCh8wCwYDVR0PBAQDAgGGMBIGCSsGAQQBgjcVAQQFAgMBAAEw
# IwYJKwYBBAGCNxUCBBYEFP3RMU7TJoqV4ZhgO6gxb6Y8vNgtMBkGCSsGAQQBgjcU
# AgQMHgoAUwB1AGIAQwBBMB8GA1UdIwQYMBaAFA6sgmBAVieX5SUT/CrhClOVWeSk
# MFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
# Y3JsL3Byb2R1Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRI
# MEYwRAYIKwYBBQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljcm9zb2Z0Um9vdENlcnQuY3J0MA0GCSqGSIb3DQEBBQUAA4ICAQBZOT5/
# Jkav629AsTK1ausOL26oSffrX3XtTDst10OtC/7L6S0xoyPMfFCYgCFdrD0vTLqi
# qFac43C7uLT4ebVJcvc+6kF/yuEMF2nLpZwgLfoLUMRWzS3jStK8cOeoDaIDpVbg
# uIpLV/KVQpzx8+/u44YfNDy4VprwUyOFKqSCHJPilAcd8uJO+IyhyugTpZFOyBvS
# j3KVKnFtmxr4HPBT1mfMIv9cHc2ijL0nsnljVkSiUc356aNYVt2bAkVEL1/02q7U
# gjJu/KSVE+Traeepoiy+yCsQDmWOmdv1ovoSJgllOJTxeh9Ku9HhVujQeJYYXMk1
# Fl/dkx1Jji2+rTREHO4QFRoAXd01WyHOmMcJ7oUOjE9tDhNOPXwpSJxy0fNsysHs
# cKNXkld9lI2gG0gDWvfPo2cKdKU27S0vF8jmcjcS9G+xPGeC+VKyjTMWZR4Oit0Q
# 3mT0b85G1NMX6XnEBLTT+yzfH4qerAr7EydAreT54al/RrsHYEdlYEBOsELsTu2z
# dnnYCjQJbRyAMR/iDlTd5aH75UcQrWSY/1AWLny/BSF64pVBJ2nDk4+VyY3YmyGu
# DVyc8KKuhmiDDGotu3ZrAB2WrfIWe/YWgyS5iM9qqEcxL5rc43E91wB+YkfRzojJ
# uBj6DnKNwaM9rwJAav9pm5biEKgQtDdQCNbDPTCCBgcwggPvoAMCAQICCmEWaDQA
# AAAAABwwDQYJKoZIhvcNAQEFBQAwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5MB4XDTA3MDQwMzEyNTMwOVoXDTIxMDQwMzEz
# MDMwOVowdzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8G
# A1UEAxMYTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAn6Fssd/bSJIqfGsuGeG94uPFmVEjUK3O3RhOJA/u0afR
# TK10MCAR6wfVVJUVSZQbQpKumFwwJtoAa+h7veyJBw/3DgSY8InMH8szJIed8vRn
# HCz8e+eIHernTqOhwSNTyo36Rc8J0F6v0LBCBKL5pmyTZ9co3EZTsIbQ5ShGLies
# hk9VUgzkAyz7apCQMG6H81kwnfp+1pez6CGXfvjSE/MIt1NtUrRFkJ9IAEpHZhEn
# KWaol+TTBoFKovmEpxFHFAmCn4TtVXj+AZodUAiFABAwRu233iNGu8QtVJ+vHnhB
# MXfMm987g5OhYQK1HQ2x/PebsgHOIktU//kFw8IgCwIDAQABo4IBqzCCAacwDwYD
# VR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUIzT42VJGcArtQPt2+7MrsMM1sw8wCwYD
# VR0PBAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMIGYBgNVHSMEgZAwgY2AFA6sgmBA
# VieX5SUT/CrhClOVWeSkoWOkYTBfMRMwEQYKCZImiZPyLGQBGRYDY29tMRkwFwYK
# CZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQDEyRNaWNyb3NvZnQgUm9vdCBD
# ZXJ0aWZpY2F0ZSBBdXRob3JpdHmCEHmtFqFKoKWtTHNY9AcTLmUwUAYDVR0fBEkw
# RzBFoEOgQYY/aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVj
# dHMvbWljcm9zb2Z0cm9vdGNlcnQuY3JsMFQGCCsGAQUFBwEBBEgwRjBEBggrBgEF
# BQcwAoY4aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNyb3Nv
# ZnRSb290Q2VydC5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEF
# BQADggIBABCXisNcA0Q23em0rXfbznlRTQGxLnRxW20ME6vOvnuPuC7UEqKMbWK4
# VwLLTiATUJndekDiV7uvWJoc4R0Bhqy7ePKL0Ow7Ae7ivo8KBciNSOLwUxXdT6uS
# 5OeNatWAweaU8gYvhQPpkSokInD79vzkeJkuDfcH4nC8GE6djmsKcpW4oTmcZy3F
# UQ7qYlw/FpiLID/iBxoy+cwxSnYxPStyC8jqcD3/hQoT38IKYY7w17gX606Lf8U1
# K16jv+u8fQtCe9RTciHuMMq7eGVcWwEXChQO0toUmPU8uWZYsy0v5/mFhsxRVuid
# cJRsrDlM1PZ5v6oYemIp76KbKTQGdxpiyT0ebR+C8AvHLLvPQ7Pl+ex9teOkqHQ1
# uE7FcSMSJnYLPFKMcVpGQxS8s7OwTWfIn0L/gHkhgJ4VMGboQhJeGsieIiHQQ+kr
# 6bv0SMws1NgygEwmKkgkX1rqVu+m3pmdyjpvvYEndAYR7nYhv5uCwSdUtrFqPYmh
# dmG0bqETpr+qR/ASb/2KMmyy/t9RyIwjyWa9nR2HEmQCPS2vWY+45CHltbDKY7R4
# VAXUQS5QrJSwpXirs6CWdRrZkocTdSIvMqgIbqBbjCW/oO+EyiHW6x5PyZruSeD3
# AWVviQt9yGnI5m7qp5fOMSn/DsVbXNhNG6HY+i+ePy5VFmvJE6P9MYIElzCCBJMC
# AQEwgZAweTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEjMCEG
# A1UEAxMaTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0ECEzMAAAEKLHmu13l7pqwA
# AQAAAQowCQYFKw4DAhoFAKCBsDAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAc
# BgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQURlUi
# 0vMHzmZ+p4ZmDdQvs1cbf4cwUAYKKwYBBAGCNwIBDDFCMECgFoAUAFAAbwB3AGUA
# cgBTAGgAZQBsAGyhJoAkaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL1Bvd2VyU2hl
# bGwgMA0GCSqGSIb3DQEBAQUABIIBAB990K8RXaZACMJx0erANRCWl5r3v36S3M9b
# hINX9ZA9jxrODRTiI2K65vO5rwwu3OZwEbktJ+fv3iuQQms2LxmIQ4wf96CWqf+I
# n/cA84Wxz10mG4ebCE8271rm+/3fumUXAwxHxeb+yAqlzXQvvJ6f4PpQSzJc/z0/
# V7gsZ/ECZlQDvFllgUE/WYoYEsqwFL3EGGLpYGIEvG2R7at8bXpYXMYFAEhw/fyo
# xkWEd5we9TvewY6yDKKbAxvtwzgDqV7gCyd8puU/HSV2p8GFRWfcjLezl7V0e2RJ
# C6GWKizU/aY/s6Na8qg75orb+2ZqUAjExeu7SPILsVYV3smbOwyhggIoMIICJAYJ
# KoZIhvcNAQkGMYICFTCCAhECAQEwgY4wdzELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# AhMzAAAAkkyir1UnCC51AAAAAACSMAkGBSsOAwIaBQCgXTAYBgkqhkiG9w0BCQMx
# CwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0xNjA0MDUwMDMyNThaMCMGCSqG
# SIb3DQEJBDEWBBSed5C/hLzSqBV6eKNlLl+iBNnGUTANBgkqhkiG9w0BAQUFAASC
# AQCpmpSaPXLsu0aZTSN4fn1sBUvfqSK0RsGFn4/u70Wg+/t6YHFXA+qisB4xUgDH
# UBYlsalRt02QXLm1mgZqavqVl0YR7SoxOnYBvKuVo0qQUlPK3UooYHzL6LLWriM8
# jq3IcOnsyWs8MNVpK2pq+DyHKI6kOupV1++BTKJ43lIiIMKT7nl3XJ0lzmCT4Zp6
# I5r1Eeqw79dG9ec/y0Rp6PUyyE1JlFiVtP6fHC5P34qttlCvD9zsSp5ALM0WT/9k
# p1j+kapKWApI1CeyKSgaOwDpHoq0QscnaRL8W1W7GfA3h4SyPoTAzIlQXjhTdOQ9
# FJ3gsXde0yeXWzY0ifZxPhId
# SIG # End signature block
