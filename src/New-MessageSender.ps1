function New-MessageSender {
<#
.SYNOPSIS
Creates a message sender to the Service Bus Message Factory.


.DESCRIPTION
Creates a message sender to the Service Bus Message Factory.


.OUTPUTS
This Cmdlet returns a SbmpMessageSender object with references to the MessageFactory of the application. On failure it returns $null.


.INPUTS
See PARAMETER section for a description of input parameters.


.EXAMPLE
$sender = New-MessageSender;
$sender

Creates a message sender to the Service Bus Message Factory with default credentials (current user) and against server defined within module configuration xml file.

	
#>
[CmdletBinding(
	HelpURI = 'http://dfch.biz/biz/dfch/PS/AzureServiceBus/Client/'
)]
[OutputType([Microsoft.ServiceBus.Messaging.MessageSender])]
Param 
(
	# [Optional] The MessageFactory. If you do not 
	# specify this value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 0)]
	$MessageFactory = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).MessageFactory
	, 
	# [Optional] The QueueName such as 'MyQueue'. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 1)]
	[string] $QueueName = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).DefaultQueueName
	, 
	# Encrypted credentials as [System.Management.Automation.PSCredential] with 
	# which to perform login. Default is credential as specified in the module 
	# configuration file.
	[Parameter(Mandatory = $false, Position = 2)]
	[alias("cred")]
	$Credential = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).Credential
)

BEGIN 
{
	$datBegin = [datetime]::Now;
	[string] $fn = $MyInvocation.MyCommand.Name;
	Log-Debug $fn ("CALL. MessageFactory Endpoint '{0}'; QueueName '{1}'; Username '{2}'" -f $MessageFactory.Address.AbsolutePath, $QueueName, $Credential.Username ) -fac 1;
	
	# Check MessageFactory connection
	if ( $MessageFactory -isnot [Microsoft.ServiceBus.Messaging.MessagingFactory] ) {
		$msg = "MessageFactory: Parameter validation FAILED. Connect to the message factory before using the Cmdlet.";
		$e = New-CustomErrorRecord -m $msg -cat InvalidData -o $svc.Core;
		$PSCmdlet.ThrowTerminatingError($e);
	}
	
	# Check MessageFactory status
	if ( $MessageFactory.IsClosed ) {
		Log-Info $fn ("MessageFactory Endpoint '{0}' is closed -> reconnect" -f $MessageFactory.Address.AbsolutePath, $QueueName, $Credential.Username ) -fac 1;
		[Microsoft.ServiceBus.Messaging.MessagingFactory] $MessageFactory = Enter-ServiceBus -EndpointServerName $MessageFactory.Address.Host -RuntimePort $MessageFactory.Address.Port -Namespace $MessageFactory.Address.Segments[-1];
	}
}
# BEGIN 

PROCESS 
{

[boolean] $fReturn = $false;

try 
{
	# Parameter validation
	# N/A
	
	# Prepare MessageClient
	[Microsoft.ServiceBus.Messaging.MessageSender] $MessageSenderClient = $null;
	# Get MessageClient from global
	if ( (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).MessageClient -is [Microsoft.ServiceBus.Messaging.MessageSender] ) {
		if ( !(Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).MessageClient.IsClosed -and (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).MessageClient.Path -eq $QueueName  ) {
			[Microsoft.ServiceBus.Messaging.MessageSender] $MessageSenderClient = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).MessageClient;
		}
	}

	# Create MessageClient
	if ( $MessageSenderClient -eq $null ) {
		[Microsoft.ServiceBus.Messaging.MessageSender] $MessageSenderClient = $MessageFactory.CreateMessageSender($QueueName);	
	}
	(Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).MessageClient = $MessageSenderClient;
	
	$OutputParameter = $MessageSenderClient;
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

if($MyInvocation.ScriptName) { Export-ModuleMember -Function New-MessageSender; } 

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
