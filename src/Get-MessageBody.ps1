function Get-MessageBody {
<#
.SYNOPSIS
Get the message body from a Service Bus Message.


.DESCRIPTION
Get the message body from a Service Bus Message.


.OUTPUTS
This Cmdlet returns the Body as [String] from the MessageFactory Message object. On failure it returns $null.


.INPUTS
See PARAMETER section for a description of input parameters.


.EXAMPLE
$message = Get-MessageBody -Message (Get-Message);

Get the message body from a Service Bus Message.
Attention: 

	
#>
[CmdletBinding(
	HelpURI = 'http://dfch.biz/biz/dfch/PS/AzureServiceBus/Client/'
)]
[OutputType([String])]
Param 
(
	# [Required] Service Bus Message
	[Parameter(Mandatory = $true, Position = 0)]
	[ValidateNotNullorEmpty()]
	[Microsoft.ServiceBus.Messaging.BrokeredMessage] $Message
)

BEGIN 
{
	$datBegin = [datetime]::Now;
	[string] $fn = $MyInvocation.MyCommand.Name;
	Log-Debug $fn ("CALL.") -fac 1;

}
# BEGIN 

PROCESS 
{

[boolean] $fReturn = $false;

try 
{
	# Parameter validation
	#N/A

	# Get Message Body
	try 
	{
		$OutputParameter = Invoke-SBGenericMethod -InputObject $Message -MethodName 'GetBody' -GenericType 'String';
		$fReturn = $true;
	} 
	catch 
	{
		$msg = $_.Exception.Message;
		$e = New-CustomErrorRecord -m $msg -cat InvalidData -o $Message;
		Log-Error $fn -msg $msg;
		$PSCmdlet.ThrowTerminatingError($e);
	}

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

if($MyInvocation.ScriptName) { Export-ModuleMember -Function Get-MessageBody; } 

# 
# Copyright 2015 d-fens GmbH
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

