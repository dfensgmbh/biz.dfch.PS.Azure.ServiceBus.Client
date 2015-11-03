function New-Message {
<#
.SYNOPSIS
Creates a message for the Service Bus Message Factory.


.DESCRIPTION
Creates a message for the Service Bus Message Factory.


.OUTPUTS
This Cmdlet returns the SequenceNumber from the MessageFactory Message object. On failure it returns $null.


.INPUTS
See PARAMETER section for a description of input parameters.


.EXAMPLE
$messageid = New-Message;
$messageid

Creates a message for the Service Bus Message Factory and against server defined within module configuration xml file.

	
#>
[CmdletBinding(
	HelpURI = 'http://dfch.biz/biz/dfch/PS/AzureServiceBus/Client/'
)]
[OutputType([string])]
Param 
(
	# [Required] The Message such as 'Message 123'.
	[Parameter(Mandatory = $true, Position = 0)]
	[ValidateNotNullorEmpty()]
	$Message
	, 
	# [Optional] Sets a application specific label.
	[Parameter(Mandatory = $false, Position = 1)]
	[string] $MessageLabel
	, 
	# [Optional] Sets addional message properties.
	[Parameter(Mandatory = $false, Position = 1)]
	[hashtable] $MessageProperties
	, 
	# [Optional] The TimeToLive is the duration after which the message expires, starting from when the message is sent to the Service Bus.
	[Parameter(Mandatory = $false, Position = 2)]
	[ValidateNotNullorEmpty()]
	[int] $MessageTimeToLiveSec
	, 
	# [Optional] The QueueName such as 'MyQueue'. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 3)]
	[ValidateNotNullorEmpty()]
	[string] $QueueName = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).DefaultQueueName
	, 
	# [Optional] The Format such as 'JSON'. If you do not specify this 
	# value it is taken from the module configuration file.
	[Parameter(Mandatory = $false, Position = 4)]
	[ValidateNotNullorEmpty()]
	[string] $MessageFormat = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).Format
	, 
	# Encrypted credentials as [System.Management.Automation.PSCredential] with 
	# which to perform login. Default is credential as specified in the module 
	# configuration file.
	[Parameter(Mandatory = $false, Position = 5)]
	[alias("cred")]
	$Credential = (Get-Variable -Name $MyInvocation.MyCommand.Module.PrivateData.MODULEVAR -ValueOnly).Credential
)

BEGIN 
{
	$datBegin = [datetime]::Now;
	[string] $fn = $MyInvocation.MyCommand.Name;
	Log-Debug $fn ("CALL. QueueName '{0}'; Username '{1}'" -f $QueueName, $Credential.Username ) -fac 1;

}
# BEGIN 

PROCESS 
{

[boolean] $fReturn = $false;

try 
{
	# Parameter validation
	# N/A
	
	# Create MessageClient
	try {
		$MessageClient = New-MessageSender -QueueName $QueueName;
	} catch {
		$msg = $_.Exception.Message;
		$e = New-CustomErrorRecord -m $msg -cat InvalidData -o $MessageClient;
		Log-Error $fn -msg $msg;
		$PSCmdlet.ThrowTerminatingError($e);
	}

	# Convert message body
	$MessageBody = $Message.ToString();
	# switch($MessageFormat) 
	# {
		# 'xml' { $InputParameter = (ConvertTo-Xml -InputObject $Message).OuterXml; }
		# 'xml-pretty' { $InputParameter = Format-Xml -String (ConvertTo-Xml -InputObject $Message).OuterXml; }
		# 'json' { $InputParameter = ConvertTo-Json -InputObject $Message -Compress; }
		# 'json-pretty' { $InputParameter = ConvertTo-Json -InputObject $Message; }
		# Default { $InputParameter = $Message; }
	# }
	
	Log-Debug $fn ("-> InputParameter '{0}'; Type '{1}'" -f $InputParameter.toString(), $InputParameter.GetType() );
	Log-Debug $fn ("-> As '{0}'; Type '{1}'" -f $MessageFormat.toString(), $MessageFormat.GetType() );
		
	# Create Message
	[Microsoft.ServiceBus.Messaging.BrokeredMessage] $BrokeredMessage = [Microsoft.ServiceBus.Messaging.BrokeredMessage]($MessageBody.ToString());
	$BrokeredMessage.Properties['Body'] = $MessageBody.ToString();
	$BrokeredMessage.Properties['BodyAs'] = $MessageFormat.ToString();
	if ( $PSBoundParameters.ContainsKey('MessageProperties') ) {
		foreach ( $MessageProperty in $MessageProperties.GetEnumerator() ) {
			$BrokeredMessage.Properties[$MessageProperty.Name] = $MessageProperty.Value.ToString();
		}
	}
	if ( $PSBoundParameters.ContainsKey('MessageLabel') ) {
		$BrokeredMessage.Label = $MessageLabel;
	}
	if ( $PSBoundParameters.ContainsKey('MessageTimeToLiveSec') ) {
		$BrokeredMessage.TimeToLive = (New-TimeSpan -Seconds $MessageTimeToLiveSec);
	}	
	
	try {
		$MessageClient.Send($BrokeredMessage);	
	} catch {
		$msg = $_.Exception.Message;
		$e = New-CustomErrorRecord -m $msg -cat InvalidData -o $MessageClient;
		Log-Error $fn -msg $msg;
		$PSCmdlet.ThrowTerminatingError($e);
	}
	
	$OutputParameter = $BrokeredMessage.MessageId;
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

if($MyInvocation.ScriptName) { Export-ModuleMember -Function New-Message; } 

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
