function Enter-ServiceBus {
<#
.SYNOPSIS
Performs a login to the Service Bus Message Factory.


.DESCRIPTION
Performs a login to the Service Bus Message Factory.

This is the first Cmdlet to be executed and required for all other Cmdlets of this module. It creates service references to the routers of the application.


.OUTPUTS
This Cmdlet returns a SbmpMessagingFactory object with references to the MessageFactory of the application. On failure it returns $null.


.INPUTS
See PARAMETER section for a description of input parameters.


.EXAMPLE
$svc = Enter-ServiceBus;
$svc

Performs a login to the Service Bus Message Factory with default credentials (current user) and against server defined within module configuration xml file.


#>
[CmdletBinding(
	HelpURI = 'http://dfch.biz/biz/dfch/PS/AzureServiceBus/Client/'
)]
[OutputType([Microsoft.ServiceBus.Messaging.MessagingFactory])]
Param 
(
	# [Optional] The EndpointServerName such as 'localhost'. If you do not 
	# specify this value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 0)]
	[ValidateNotNullorEmpty()]
	[string] $EndpointServerName = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).EndpointServerName
	, 
	# [Optional] The RuntimePort such as '123'. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 1)]
	[int] $RuntimePort = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).RuntimePort
	, 
	# [Optional] The ManagementPort such as '123'. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 2)]
	[int] $ManagementPort = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).ManagementPort	
	,
	# [Optional] The Namespace such as 'ServiceBusDefaultNamespace'. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 3)]
	[string] $Namespace = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).DefaultNameSpace
	, 
	# Encrypted credentials as [System.Management.Automation.PSCredential] with 
	# which to perform login. Default is credential as specified in the module 
	# configuration file.
	[Parameter(Mandatory = $false, Position = 4)]
	[alias("cred")]
	$Credential = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).Credential
)

BEGIN 
{
	$datBegin = [datetime]::Now;
	[string] $fn = $MyInvocation.MyCommand.Name;
	Log-Debug $fn ("CALL. EndpointServerName '{0}'; RuntimePort '{1}'; Namespace '{2}'; Username '{3}'" -f $EndpointServerName, $RuntimePort, $Namespace, $Credential.Username ) -fac 1;
}
# BEGIN 

PROCESS 
{

[boolean] $fReturn = $false;

try 
{
	# Parameter validation
	# N/A
	
	# Prepare connection string
	$ConnectionString = 'Endpoint=sb://{0}/{1};StsEndpoint=https://{0}:{3}/{1};RuntimePort={2};ManagementPort={3}' -f $EndpointServerName, $Namespace, $RuntimePort, $ManagementPort;
	
	# Create message factory
	(Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).MessageFactory = [Microsoft.ServiceBus.Messaging.MessagingFactory]::CreateFromConnectionString($ConnectionString);
	
	$OutputParameter = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).MessageFactory;
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

Set-Alias -Name Connect- -Value 'Enter-ServiceBus';
Set-Alias -Name Enter- -Value 'Enter-ServiceBus';
if($MyInvocation.ScriptName) { Export-ModuleMember -Function Enter-ServiceBus -Alias Connect-, Enter-; } 

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
