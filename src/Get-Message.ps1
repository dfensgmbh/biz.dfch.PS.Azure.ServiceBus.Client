function Get-Message {
<#
.SYNOPSIS
Receives a message from a receiver client, which is based on the Service Bus Messaging Factory.

.DESCRIPTION
Receives a message from a receiver client, which is based on the Service Bus Messaging Factory.

.OUTPUTS
This Cmdlet returns the Messaging Factory message object. In case of failure is trying '-Retry' times, otherwise returns $null.

.INPUTS
See PARAMETER section for a description of input parameters.

.EXAMPLE
$message = Get-Message -BodyAsProperty;
write-host $message.Properties['Body']

.EXAMPLE
$message = Get-Message -ReceiveAndDelete;

.EXAMPLE
$message = Get-Message -Receivemode 'PeekLock';
...do something
$message.Complete();

.EXAMPLE
$message = Get-Message -Facility 'Topic-Newsletter' -EnsureFacility;

.EXAMPLE
$receiver = Get-MessageReceiver -Facility 'MyQueue1';
$message = Get-Message -Client $receiver;

Receives a message from a receiver client, which is based on the Service Bus Messaging Factory against server defined within module configuration xml file.
#>
[CmdletBinding(
	HelpURI = 'http://dfch.biz/biz/dfch/PS/AzureServiceBus/Client/'
)]
[OutputType([Microsoft.ServiceBus.Messaging.BrokeredMessage])]
Param 
(
	# [Optional] The WaitTimeOutSec such as '3' Seconds for receiving a message before it times out. If you do not specify this 
	# value it is taken from the default value = 3 sec.
	[Parameter(Mandatory = $false, Position = 0)]
	[ValidateNotNullorEmpty()]
	[int] $WaitTimeoutSec = [int]::MaxValue
	, 
	# [Optional] The Receivemode such as 'PeekLock'. If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 1)]
	[ValidateSet('PeekLock', 'ReceiveAndDelete')]
	[string] $Receivemode = 'ReceiveAndDelete'
	,
	# [Optional] ReceiveAndDelete same as Receivemode 'ReceiveAndDelete'. If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 2)]
	[switch] $ReceiveAndDelete = $false
	,
	# [Optional] ReceiveAndComplete same as Receivemode 'PeekLock' and $Message.Complete(). If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 3)]
	[switch] $ReceiveAndComplete = $false
	,
	# [Optional] ReceiveAndAbandon same as Receivemode 'PeekLock' and $Message.Abandon(). If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 4)]
	[switch] $ReceiveAndAbandon = $false
	,
	# [Optional] BodyAsProperty writes the Message Body to Property 'Body'. If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 5)]
	[switch] $BodyAsProperty = $false
	,
	# [Optional] The Facility such as 'MyQueue'. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 6)]
	[ValidateNotNullorEmpty()]
	[alias("queue")]
	[alias("subscription")]
	[alias("QueueName")]
	[string] $Facility = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).ReceiveFacility
	, 
	# [Optional] Checks if facility existing
	[Parameter(Mandatory = $false, Position = 7)]
	[alias("ensure")]
	[alias("broadcast")]
	[alias("checkfacility")]
	[switch]$EnsureFacility = $false
	,
	# [Optional] Messaging Client (instance of the MessagingFactory)
	[Parameter(Mandatory = $false, Position = 8)]
	[alias("MessageClient")]
	$Client
	,
	# Encrypted credentials as [System.Management.Automation.PSCredential] with 
	# which to perform login. Default is credential as specified in the module 
	# configuration file.
	[Parameter(Mandatory = $false, Position = 9)]
	[alias("cred")]
	$Credential = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).Credential
	,
	# [Optional] Skip retrying
	[Parameter(Mandatory = $false, Position = 10)]
	[switch]$NoRetry = $false
	,
	# [Optional] The Retry. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory=$false, Position = 11)]
	[int]$Retry = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).CommandRetry
	,
	# [Optional] The RetryInterval. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory=$false, Position = 12)]
	[int]$RetryInterval = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).CommandRetryInterval
)

BEGIN 
{
	$datBegin = [datetime]::Now;
	[string] $fn = $MyInvocation.MyCommand.Name;
	Log-Debug $fn ("CALL. Facility '{0}'; Username '{1}'" -f $Facility, $Credential.Username ) -fac 1;

}
# BEGIN 

PROCESS 
{

	[boolean] $fReturn = $false;

	# Get all parameters
	$Params = @{};
	$ParamsList = (Get-Command -Name $MyInvocation.InvocationName).Parameters;
	foreach ($key in $ParamsList.keys)
	{
		$var = Get-Variable -Name $key -ErrorAction SilentlyContinue;
		if($var)
		{
			if ( @('Retry', 'RetryInterval', 'NoRetry') -notcontains $($var.name) -and $var.value -ne $null -and $($var.value) -ne '' )  
			{
				$Params.Add($($var.name), $var.value);
			}
		}
	}
	Log-Debug $fn ("Operation [{0}] arguments: {1}" -f ($fn -replace 'Worker', ''), ($Params | Out-String));
	
	# Retry handling
	for($c = 1; $c -le ($Retry+1); $c++)
	{
		try
		{
			$OutputParameter = Get-MessageWorker @Params;
			break;
		}
		catch
		{
			# Throw last execption
			if ( $NoRetry -or 
				$c -gt $Retry -or 
				$_.Exception.Message -match 'Connect to the message factory before using the Cmdlet.' 
				)
			{
				if ($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent) 
				{
					throw;
				}
				else
				{
					break;
				}	
			}
			Log-Debug $fn ("[{0}/{1}] Retrying operation [{2}]" -f $c, $Retry, ($fn -replace 'Worker', ''));
			Start-Sleep -Seconds $RetryInterval;
			$RetryInterval *= 2;
			continue;
		}
	}
	return $OutputParameter;
	$fReturn = $true;

}
# PROCESS

END 
{
	$datEnd = [datetime]::Now;
	Log-Debug -fn $fn -msg ("RET. fReturn: [{0}]. Execution time: [{1}]ms. Started: [{2}]." -f $fReturn, ($datEnd - $datBegin).TotalMilliseconds, $datBegin.ToString('yyyy-MM-dd HH:mm:ss.fffzzz')) -fac 2;
}
# END

} # function
if($MyInvocation.ScriptName) { Export-ModuleMember -Function Get-Message; } 

function Get-MessageWorker {
<#
.SYNOPSIS
Receives a message from a receiver client, which is based on the Service Bus Messaging Factory.

.DESCRIPTION
Receives a message from a receiver client, which is based on the Service Bus Messaging Factory.

.OUTPUTS
This Cmdlet returns the MessageId from the Messaging Factory message object. On failure it returns $null.

.INPUTS
See PARAMETER section for a description of input parameters.

.EXAMPLE
$message = Get-MessageWorker;

Receives a message from a receiver client, which is based on the Service Bus Messaging Factory.
#>
[CmdletBinding(
	HelpURI = 'http://dfch.biz/biz/dfch/PS/AzureServiceBus/Client/'
)]
[OutputType([Microsoft.ServiceBus.Messaging.BrokeredMessage])]
Param 
(
	# [Optional] The WaitTimeOutSec such as '3' Seconds for receiving a message before it times out. If you do not specify this 
	# value it is taken from the default value = 3 sec.
	[Parameter(Mandatory = $false, Position = 0)]
	[ValidateNotNullorEmpty()]
	[int] $WaitTimeoutSec = [int]::MaxValue
	, 
	# [Optional] The Receivemode such as 'PeekLock'. If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 1)]
	[ValidateSet('PeekLock', 'ReceiveAndDelete')]
	[string] $Receivemode = 'ReceiveAndDelete'
	,
	# [Optional] ReceiveAndDelete same as Receivemode 'ReceiveAndDelete'. If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 2)]
	[switch] $ReceiveAndDelete = $false
	,
	# [Optional] ReceiveAndComplete same as Receivemode 'PeekLock' and $Message.Complete(). If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 3)]
	[switch] $ReceiveAndComplete = $false
	,
	# [Optional] ReceiveAndAbandon same as Receivemode 'PeekLock' and $Message.Abandon(). If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 4)]
	[switch] $ReceiveAndAbandon = $false
	,
	# [Optional] BodyAsProperty writes the Message Body to Property 'Body'. If you do not specify this 
	# value it is taken from the default parameter.
	[Parameter(Mandatory = $false, Position = 5)]
	[switch] $BodyAsProperty = $false
	,
	# [Optional] The Facility such as 'MyQueue'. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 6)]
	[ValidateNotNullorEmpty()]
	[alias("queue")]
	[alias("subscription")]
	[alias("QueueName")]
	[string] $Facility = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).ReceiveFacility
	, 
	# [Optional] Checks if facility existing
	[Parameter(Mandatory = $false, Position = 7)]
	[alias("ensure")]
	[alias("broadcast")]
	[alias("checkfacility")]
	[switch]$EnsureFacility = $false
	,
	# [Optional] Messaging Client (instance of the MessagingFactory)
	[Parameter(Mandatory = $false, Position = 8)]
	[alias("MessageClient")]
	$Client
	,
	# Encrypted credentials as [System.Management.Automation.PSCredential] with 
	# which to perform login. Default is credential as specified in the module 
	# configuration file.
	[Parameter(Mandatory = $false, Position = 9)]
	[alias("cred")]
	$Credential = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).Credential
)

BEGIN 
{
	$datBegin = [datetime]::Now;
	[string] $fn = $MyInvocation.MyCommand.Name;
	Log-Debug $fn ("CALL. Facility '{0}'; Username '{1}'" -f $Facility, $Credential.Username ) -fac 1;

}
# BEGIN 

PROCESS 
{

[boolean] $fReturn = $false;

try 
{
	# Parameter validation
	if ( $ReceiveAndDelete ) 
	{
		$Receivemode = 'ReceiveAndDelete';
	}
	
	# Check facility
	if ( $EnsureFacility ) 
	{
		$Path = ($Facility -Split "\\Subscriptions\\")[0];
		$SubscriptionName = "RECV-{0}" -f (get-wmiobject Win32_ComputerSystemProduct  | Select-Object -ExpandProperty UUID).toString();
		if ( $Facility -match "\\Subscriptions\\" )
		{
			$SubscriptionName = ($Facility -Split "\\Subscriptions\\")[1];
		}
		try 
		{
			$FacilitiyExists = New-MessageFacility -Path $Path -Name $SubscriptionName;
			$Facility = '{0}\Subscriptions\{1}' -f $Path, $SubscriptionName;
		} catch {
			$msg = $_.Exception.Message;
			Log-Error -msg $msg;
			$e = New-CustomErrorRecord -m $msg -cat InvalidData -o $Facility;
			$PSCmdlet.ThrowTerminatingError($e);
		}
	}
	
	# Create Client
	if ( !$PSBoundParameters.ContainsKey('Client') ) 
	{
		try 
		{
			$Client = Get-MessageReceiver -Facility $Facility -Receivemode $Receivemode;
		} 
		catch 
		{
			$msg = $_.Exception.Message;
			$e = New-CustomErrorRecord -m $msg -cat InvalidData -o $Client;
			Log-Error $fn -msg $msg;
			$PSCmdlet.ThrowTerminatingError($e);
		}
	}
	
	# Get Message
	try 
	{
		# DFTODO - is this really an AMQP message when we are using the BrokeredMessage class?, see #5
		[Microsoft.ServiceBus.Messaging.BrokeredMessage] $BrokeredMessage = $Client.Receive((New-TimeSpan -Seconds $WaitTimeoutSec));
	} catch {
		$msg = $_.Exception.Message;
		$e = New-CustomErrorRecord -m $msg -cat InvalidData -o $BrokeredMessage;
		Log-Error $fn -msg $msg;
		$PSCmdlet.ThrowTerminatingError($e);
	}
	
	# Process Message	
	if ( $ReceiveAndAbandon -and $Receivemode -ne 'ReceiveAndDelete' ) 
	{
		$BrokeredMessage.Abandon();
	}
	
	if ( $ReceiveAndComplete -and $Receivemode -ne 'ReceiveAndDelete' ) 
	{
		$BrokeredMessage.Complete();
	}
	
	if ( $BodyAsProperty ) 
	{
		$PropertyName = 'Body';
		$PropertyValue = Get-SBMessageBody $BrokeredMessage
		if ( $BrokeredMessage.Properties.ContainsKey($PropertyName) -and $BrokeredMessage.Properties[$PropertyName].toString() -ne $PropertyValue.toString() ) 
		{
			[int] $PropertyCount = 1;
			$PropertyName = ("Body{0}" -f $PropertyCount);
			while( $BrokeredMessage.Properties.ContainsKey($PropertyName) )
			{
				$PropertyCount += 1;
				$PropertyName = ("Body{0}" -f $PropertyCount);
			}
		}
		$BrokeredMessage.Properties[$PropertyName] = $PropertyValue;
	}
	
	$OutputParameter = $BrokeredMessage;
	$fReturn = $true;
}
catch 
{
	if($gotoSuccess -eq $_.Exception.Message) 
	{
			$fReturn = $true;
	} 
	else 
	{
		[string] $ErrorText = "catch [$($_.FullyQualifiedErrorId)]";
		$ErrorText += (($_ | fl * -Force) | Out-String);
		$ErrorText += (($_.Exception | fl * -Force) | Out-String);
		$ErrorText += (Get-PSCallStack | Out-String);
		
		if($_.Exception -is [System.Net.WebException]) 
		{
			Log-Critical $fn "Login to Uri '$Uri' with Username '$Username' FAILED [$_].";
			Log-Debug $fn $ErrorText -fac 3;
		}
		else 
		{
			Log-Error $fn $ErrorText -fac 3;
			if($gotoError -eq $_.Exception.Message) 
			{
				Log-Error $fn $e.Exception.Message;
				$PSCmdlet.ThrowTerminatingError($e);
			} 
			elseif($gotoFailure -ne $_.Exception.Message) 
			{ 
				Write-Verbose ("$fn`n$ErrorText"); 
			} 
			else 
			{
				# N/A
			}
		}
		$fReturn = $false;
		$OutputParameter = $null;
	}
}
finally 
{
	# Clean up
	# N/A
}
return $OutputParameter;

}
# PROCESS

END 
{
	$datEnd = [datetime]::Now;
	Log-Debug -fn $fn -msg ("RET. fReturn: [{0}]. Execution time: [{1}]ms. Started: [{2}]." -f $fReturn, ($datEnd - $datBegin).TotalMilliseconds, $datBegin.ToString('yyyy-MM-dd HH:mm:ss.fffzzz')) -fac 2;
}
# END

} # function

# 
# Copyright 2014-2015 d-fens GmbH
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 

# SIG # Begin signature block
# MIIXDwYJKoZIhvcNAQcCoIIXADCCFvwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUyQ9oPmAPCR9gIN7/6mzDIklU
# YUCgghHCMIIEFDCCAvygAwIBAgILBAAAAAABL07hUtcwDQYJKoZIhvcNAQEFBQAw
# VzELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExEDAOBgNV
# BAsTB1Jvb3QgQ0ExGzAZBgNVBAMTEkdsb2JhbFNpZ24gUm9vdCBDQTAeFw0xMTA0
# MTMxMDAwMDBaFw0yODAxMjgxMjAwMDBaMFIxCzAJBgNVBAYTAkJFMRkwFwYDVQQK
# ExBHbG9iYWxTaWduIG52LXNhMSgwJgYDVQQDEx9HbG9iYWxTaWduIFRpbWVzdGFt
# cGluZyBDQSAtIEcyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlO9l
# +LVXn6BTDTQG6wkft0cYasvwW+T/J6U00feJGr+esc0SQW5m1IGghYtkWkYvmaCN
# d7HivFzdItdqZ9C76Mp03otPDbBS5ZBb60cO8eefnAuQZT4XljBFcm05oRc2yrmg
# jBtPCBn2gTGtYRakYua0QJ7D/PuV9vu1LpWBmODvxevYAll4d/eq41JrUJEpxfz3
# zZNl0mBhIvIG+zLdFlH6Dv2KMPAXCae78wSuq5DnbN96qfTvxGInX2+ZbTh0qhGL
# 2t/HFEzphbLswn1KJo/nVrqm4M+SU4B09APsaLJgvIQgAIMboe60dAXBKY5i0Eex
# +vBTzBj5Ljv5cH60JQIDAQABo4HlMIHiMA4GA1UdDwEB/wQEAwIBBjASBgNVHRMB
# Af8ECDAGAQH/AgEAMB0GA1UdDgQWBBRG2D7/3OO+/4Pm9IWbsN1q1hSpwTBHBgNV
# HSAEQDA+MDwGBFUdIAAwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFs
# c2lnbi5jb20vcmVwb3NpdG9yeS8wMwYDVR0fBCwwKjAooCagJIYiaHR0cDovL2Ny
# bC5nbG9iYWxzaWduLm5ldC9yb290LmNybDAfBgNVHSMEGDAWgBRge2YaRQ2XyolQ
# L30EzTSo//z9SzANBgkqhkiG9w0BAQUFAAOCAQEATl5WkB5GtNlJMfO7FzkoG8IW
# 3f1B3AkFBJtvsqKa1pkuQJkAVbXqP6UgdtOGNNQXzFU6x4Lu76i6vNgGnxVQ380W
# e1I6AtcZGv2v8Hhc4EvFGN86JB7arLipWAQCBzDbsBJe/jG+8ARI9PBw+DpeVoPP
# PfsNvPTF7ZedudTbpSeE4zibi6c1hkQgpDttpGoLoYP9KOva7yj2zIhd+wo7AKvg
# IeviLzVsD440RZfroveZMzV+y5qKu0VN5z+fwtmK+mWybsd+Zf/okuEsMaL3sCc2
# SI8mbzvuTXYfecPlf5Y1vC0OzAGwjn//UYCAp5LUs0RGZIyHTxZjBzFLY7Df8zCC
# BCkwggMRoAMCAQICCwQAAAAAATGJxjfoMA0GCSqGSIb3DQEBCwUAMEwxIDAeBgNV
# BAsTF0dsb2JhbFNpZ24gUm9vdCBDQSAtIFIzMRMwEQYDVQQKEwpHbG9iYWxTaWdu
# MRMwEQYDVQQDEwpHbG9iYWxTaWduMB4XDTExMDgwMjEwMDAwMFoXDTE5MDgwMjEw
# MDAwMFowWjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2Ex
# MDAuBgNVBAMTJ0dsb2JhbFNpZ24gQ29kZVNpZ25pbmcgQ0EgLSBTSEEyNTYgLSBH
# MjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKPv0Z8p6djTgnY8YqDS
# SdYWHvHP8NC6SEMDLacd8gE0SaQQ6WIT9BP0FoO11VdCSIYrlViH6igEdMtyEQ9h
# JuH6HGEVxyibTQuCDyYrkDqW7aTQaymc9WGI5qRXb+70cNCNF97mZnZfdB5eDFM4
# XZD03zAtGxPReZhUGks4BPQHxCMD05LL94BdqpxWBkQtQUxItC3sNZKaxpXX9c6Q
# MeJ2s2G48XVXQqw7zivIkEnotybPuwyJy9DDo2qhydXjnFMrVyb+Vpp2/WFGomDs
# KUZH8s3ggmLGBFrn7U5AXEgGfZ1f53TJnoRlDVve3NMkHLQUEeurv8QfpLqZ0BdY
# Nc0CAwEAAaOB/TCB+jAOBgNVHQ8BAf8EBAMCAQYwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAdBgNVHQ4EFgQUGUq4WuRNMaUU5V7sL6Mc+oCMMmswRwYDVR0gBEAwPjA8BgRV
# HSAAMDQwMgYIKwYBBQUHAgEWJmh0dHBzOi8vd3d3Lmdsb2JhbHNpZ24uY29tL3Jl
# cG9zaXRvcnkvMDYGA1UdHwQvMC0wK6ApoCeGJWh0dHA6Ly9jcmwuZ2xvYmFsc2ln
# bi5uZXQvcm9vdC1yMy5jcmwwEwYDVR0lBAwwCgYIKwYBBQUHAwMwHwYDVR0jBBgw
# FoAUj/BLf6guRSSuTVD6Y5qL3uLdG7wwDQYJKoZIhvcNAQELBQADggEBAHmwaTTi
# BYf2/tRgLC+GeTQD4LEHkwyEXPnk3GzPbrXsCly6C9BoMS4/ZL0Pgmtmd4F/ximl
# F9jwiU2DJBH2bv6d4UgKKKDieySApOzCmgDXsG1szYjVFXjPE/mIpXNNwTYr3MvO
# 23580ovvL72zT006rbtibiiTxAzL2ebK4BEClAOwvT+UKFaQHlPCJ9XJPM0aYx6C
# WRW2QMqngarDVa8z0bV16AnqRwhIIvtdG/Mseml+xddaXlYzPK1X6JMlQsPSXnE7
# ShxU7alVrCgFx8RsXdw8k/ZpPIJRzhoVPV4Bc/9Aouq0rtOO+u5dbEfHQfXUVlfy
# GDcy1tTMS/Zx4HYwggSfMIIDh6ADAgECAhIRIQaggdM/2HrlgkzBa1IJTgMwDQYJ
# KoZIhvcNAQEFBQAwUjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24g
# bnYtc2ExKDAmBgNVBAMTH0dsb2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0gRzIw
# HhcNMTUwMjAzMDAwMDAwWhcNMjYwMzAzMDAwMDAwWjBgMQswCQYDVQQGEwJTRzEf
# MB0GA1UEChMWR01PIEdsb2JhbFNpZ24gUHRlIEx0ZDEwMC4GA1UEAxMnR2xvYmFs
# U2lnbiBUU0EgZm9yIE1TIEF1dGhlbnRpY29kZSAtIEcyMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAsBeuotO2BDBWHlgPse1VpNZUy9j2czrsXV6rJf02
# pfqEw2FAxUa1WVI7QqIuXxNiEKlb5nPWkiWxfSPjBrOHOg5D8NcAiVOiETFSKG5d
# QHI88gl3p0mSl9RskKB2p/243LOd8gdgLE9YmABr0xVU4Prd/4AsXximmP/Uq+yh
# RVmyLm9iXeDZGayLV5yoJivZF6UQ0kcIGnAsM4t/aIAqtaFda92NAgIpA6p8N7u7
# KU49U5OzpvqP0liTFUy5LauAo6Ml+6/3CGSwekQPXBDXX2E3qk5r09JTJZ2Cc/os
# +XKwqRk5KlD6qdA8OsroW+/1X1H0+QrZlzXeaoXmIwRCrwIDAQABo4IBXzCCAVsw
# DgYDVR0PAQH/BAQDAgeAMEwGA1UdIARFMEMwQQYJKwYBBAGgMgEeMDQwMgYIKwYB
# BQUHAgEWJmh0dHBzOi8vd3d3Lmdsb2JhbHNpZ24uY29tL3JlcG9zaXRvcnkvMAkG
# A1UdEwQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwQgYDVR0fBDswOTA3oDWg
# M4YxaHR0cDovL2NybC5nbG9iYWxzaWduLmNvbS9ncy9nc3RpbWVzdGFtcGluZ2cy
# LmNybDBUBggrBgEFBQcBAQRIMEYwRAYIKwYBBQUHMAKGOGh0dHA6Ly9zZWN1cmUu
# Z2xvYmFsc2lnbi5jb20vY2FjZXJ0L2dzdGltZXN0YW1waW5nZzIuY3J0MB0GA1Ud
# DgQWBBTUooRKOFoYf7pPMFC9ndV6h9YJ9zAfBgNVHSMEGDAWgBRG2D7/3OO+/4Pm
# 9IWbsN1q1hSpwTANBgkqhkiG9w0BAQUFAAOCAQEAgDLcB40coJydPCroPSGLWaFN
# fsxEzgO+fqq8xOZ7c7tL8YjakE51Nyg4Y7nXKw9UqVbOdzmXMHPNm9nZBUUcjaS4
# A11P2RwumODpiObs1wV+Vip79xZbo62PlyUShBuyXGNKCtLvEFRHgoQ1aSicDOQf
# FBYk+nXcdHJuTsrjakOvz302SNG96QaRLC+myHH9z73YnSGY/K/b3iKMr6fzd++d
# 3KNwS0Qa8HiFHvKljDm13IgcN+2tFPUHCya9vm0CXrG4sFhshToN9v9aJwzF3lPn
# VDxWTMlOTDD28lz7GozCgr6tWZH2G01Ve89bAdz9etNvI1wyR5sB88FRFEaKmzCC
# BNYwggO+oAMCAQICEhEhDRayW4wRltP+V8mGEea62TANBgkqhkiG9w0BAQsFADBa
# MQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEwMC4GA1UE
# AxMnR2xvYmFsU2lnbiBDb2RlU2lnbmluZyBDQSAtIFNIQTI1NiAtIEcyMB4XDTE1
# MDUwNDE2NDMyMVoXDTE4MDUwNDE2NDMyMVowVTELMAkGA1UEBhMCQ0gxDDAKBgNV
# BAgTA1p1ZzEMMAoGA1UEBxMDWnVnMRQwEgYDVQQKEwtkLWZlbnMgR21iSDEUMBIG
# A1UEAxMLZC1mZW5zIEdtYkgwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDNPSzSNPylU9jFM78Q/GjzB7N+VNqikf/use7p8mpnBZ4cf5b4qV3rqQd62rJH
# RlAsxgouCSNQrl8xxfg6/t/I02kPvrzsR4xnDgMiVCqVRAeQsWebafWdTvWmONBS
# lxJejPP8TSgXMKFaDa+2HleTycTBYSoErAZSWpQ0NqF9zBadjsJRVatQuPkTDrwL
# eWibiyOipK9fcNoQpl5ll5H9EG668YJR3fqX9o0TQTkOmxXIL3IJ0UxdpyDpLEkt
# tBG6Y5wAdpF2dQX2phrfFNVY54JOGtuBkNGMSiLFzTkBA1fOlA6ICMYjB8xIFxVv
# rN1tYojCrqYkKMOjwWQz5X8zAgMBAAGjggGZMIIBlTAOBgNVHQ8BAf8EBAMCB4Aw
# TAYDVR0gBEUwQzBBBgkrBgEEAaAyATIwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93
# d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9yeS8wCQYDVR0TBAIwADATBgNVHSUE
# DDAKBggrBgEFBQcDAzBCBgNVHR8EOzA5MDegNaAzhjFodHRwOi8vY3JsLmdsb2Jh
# bHNpZ24uY29tL2dzL2dzY29kZXNpZ25zaGEyZzIuY3JsMIGQBggrBgEFBQcBAQSB
# gzCBgDBEBggrBgEFBQcwAoY4aHR0cDovL3NlY3VyZS5nbG9iYWxzaWduLmNvbS9j
# YWNlcnQvZ3Njb2Rlc2lnbnNoYTJnMi5jcnQwOAYIKwYBBQUHMAGGLGh0dHA6Ly9v
# Y3NwMi5nbG9iYWxzaWduLmNvbS9nc2NvZGVzaWduc2hhMmcyMB0GA1UdDgQWBBTN
# GDddiIYZy9p3Z84iSIMd27rtUDAfBgNVHSMEGDAWgBQZSrha5E0xpRTlXuwvoxz6
# gIwyazANBgkqhkiG9w0BAQsFAAOCAQEAAApsOzSX1alF00fTeijB/aIthO3UB0ks
# 1Gg3xoKQC1iEQmFG/qlFLiufs52kRPN7L0a7ClNH3iQpaH5IEaUENT9cNEXdKTBG
# 8OrJS8lrDJXImgNEgtSwz0B40h7bM2Z+0DvXDvpmfyM2NwHF/nNVj7NzmczrLRqN
# 9de3tV0pgRqnIYordVcmb24CZl3bzpwzbQQy14Iz+P5Z2cnw+QaYzAuweTZxEUcJ
# bFwpM49c1LMPFJTuOKkUgY90JJ3gVTpyQxfkc7DNBnx74PlRzjFmeGC/hxQt0hvo
# eaAiBdjo/1uuCTToigVnyRH+c0T2AezTeoFb7ne3I538hWeTdU5q9jGCBLcwggSz
# AgEBMHAwWjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2Ex
# MDAuBgNVBAMTJ0dsb2JhbFNpZ24gQ29kZVNpZ25pbmcgQ0EgLSBTSEEyNTYgLSBH
# MgISESENFrJbjBGW0/5XyYYR5rrZMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEM
# MQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQB
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBR4PNZIZnPCem5v
# z4SKcu4+8+WFvDANBgkqhkiG9w0BAQEFAASCAQDHEr0aFKD/qRQPxpXfsudEJ3ZJ
# lQMUt2m4Lsy6eC2wwfEv4CPU85Y1gdRZmPF9Wb92RJVkZYfNi2eNuM869RzaMwX+
# jv9ecPXSfZSdHywRL5KTa2E6tUlFqBQaMxOGuX2TfjB04NpjZo3aq8+kxy90vHpu
# aXe/YBhc2X8oXkEFhRXQjANFSchhXwXUrYfBK6SFxkDBuse+E3jCzZFUfmAMXPh7
# E/CmKXRGsKkuoc2d38JHFE5/zcn/leS0Djd+8IN47idQLwTAfB+rIV9UTljDEqM4
# avInr5TuMR95IKOQRBldYwsXSOLzDAWmtKKTdDzla3E6xO+l20r+aCegrVphoYIC
# ojCCAp4GCSqGSIb3DQEJBjGCAo8wggKLAgEBMGgwUjELMAkGA1UEBhMCQkUxGTAX
# BgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExKDAmBgNVBAMTH0dsb2JhbFNpZ24gVGlt
# ZXN0YW1waW5nIENBIC0gRzICEhEhBqCB0z/YeuWCTMFrUglOAzAJBgUrDgMCGgUA
# oIH9MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1
# MTEwNDE0MzkxNFowIwYJKoZIhvcNAQkEMRYEFIYYEArbT1a8IKjveSsn7qZEQtmV
# MIGdBgsqhkiG9w0BCRACDDGBjTCBijCBhzCBhAQUs2MItNTN7U/PvWa5Vfrjv7Es
# KeYwbDBWpFQwUjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYt
# c2ExKDAmBgNVBAMTH0dsb2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0gRzICEhEh
# BqCB0z/YeuWCTMFrUglOAzANBgkqhkiG9w0BAQEFAASCAQAWcqDz/ye1cOSv+t6/
# nIeypRVR1pBb0IZ2pnmqeVNvEcwymUcwQx5U6XZN/0aag1fjc1QGsJ9AKTn5z5xE
# azkXEONgi4F88ubC2G29q2iNA0JEu+6AdCvcvOIdnv+1DQ8IE+1w2SKMHXjxU7QA
# 20U91YER2y6BOiuXuSo1jTRsoxS5nyqeSUCtwgrkaIAbGZ4BjCJppFwvMByyaLjV
# eaRagVSiLLvoXSQlWbckaWdmW13ws20OD0X919go2OeaH7m1YKVurBlqL/IVy35F
# r426/+VK50mMGxYfXn7dzp4c0dT2Ptq2OjmrvqgiPP+oEb2aD7YVSZzALEUNWBuB
# rBid
# SIG # End signature block
