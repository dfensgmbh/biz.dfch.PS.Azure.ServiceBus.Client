$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")

function Stop-Pester($message = "EMERGENCY: Script cannot continue.")
{
	$msg = $message;
	$e = New-CustomErrorRecord -msg $msg -cat OperationStopped -o $msg;
	$PSCmdlet.ThrowTerminatingError($e);
}

Describe -Tags "SBClientBroadcast.Tests" "SBClientBroadcast.Tests" {

	Mock Export-ModuleMember { return $null; }
	
	. "$here\$sut"
	
	Context "#CLOUDTCL-1893-SBClientBroadcastTests" {
		BeforeEach {		
			# Import management module for service bus - required to create, check and delete queues/topis/subscriptions
			$moduleName = 'biz.dfch.PS.Azure.ServiceBus.Management';
			Remove-Module $moduleName -ErrorAction:SilentlyContinue;
			Remove-Variable biz_dfch_PS_Azure_ServiceBus_Management -ErrorAction:SilentlyContinue;
			Import-Module $moduleName -ErrorAction:SilentlyContinue;
			
			# Import client module for service bus - required to send and receive messages
			$moduleName = "biz.dfch.PS.Azure.ServiceBus.Client";			
			Remove-Module $moduleName -ErrorAction:SilentlyContinue;
			Remove-Variable biz_dfch_PS_Azure_ServiceBus_Client -ErrorAction:SilentlyContinue;
			Import-Module $moduleName -ErrorAction:SilentlyContinue -Force;
			
			# Set variable to the loacal environment
			$biz_dfch_PS_Azure_ServiceBus_Client.EndpointServerName = (Get-SBFarm).Hosts[0].Name;
			$biz_dfch_PS_Azure_ServiceBus_Client.NameSpace = (Get-SBNamespace).Name;
			$biz_dfch_PS_Azure_ServiceBus_Management.DefaultNameSpace = $biz_dfch_PS_Azure_ServiceBus_Client.NameSpace;
			$biz_dfch_PS_Azure_ServiceBus_Client.SharedAccessKeyName = (Get-SBAuthorizationRule -NamespaceName $biz_dfch_PS_Azure_ServiceBus_Client.NameSpace -Name RootManageSharedAccessKey).KeyName;
			$biz_dfch_PS_Azure_ServiceBus_Client.SharedAccessKey = (Get-SBAuthorizationRule -NamespaceName $biz_dfch_PS_Azure_ServiceBus_Client.NameSpace -Name RootManageSharedAccessKey).PrimaryKey;
			
			# Create Topic
			$guid = [guid]::NewGuid().ToString();
			$topicName = "Pester-{0}" -f $guid;
			New-SBTopic -Path $topicName;
			
			# Enter Servicebus
			$enterSBServer = Enter-SBServer;
		}
		
		AfterEach {
			#Cleanup - Delete Topic and all relatet subscriptions and messages
			Remove-SBTopic -Path $topicName -force;
		}
				
		It "SBClientBroadcast-SendAndAllRecipientsLockMessages" -Test {
		
			<#
				No real test case available...
			#>
		
			##########################################################
			# Arrange
			##########################################################
			$pathMessageHelper = "$here\getMessageHelper.ps1"

			# Arrange test parameter
			$receiveMode = 'PeekLock';
			$waitTimeoutSec = 10;
			$amountOfReceiver = 5;
			$receiveCyclesPerReceiver = 10;
			$amountMessageSender = 3;
			$messageAmount = 5;
			$numberOfSender = 3;
			$messageText = "TestMessageBroadcast"
			
			# Arrange MessageReceiver (separate sessions)
			$newJobs = New-Object System.Collections.ArrayList
			$subscriptionPaths = New-Object System.Collections.ArrayList;
			$guid = [guid]::NewGuid().ToString();

			for ($i=1; $i -le $amountOfReceiver; $i++)
			{
				# Arrange Subscriptions
				$subscriptionName = 'Pester-{0}-{1}' -f $guid, $i;
				$subscriptionPath = "{0}\Subscriptions\{1}" -f $topicName, $subscriptionName;
				$subscriptionPaths.Add($subscriptionPath);
				New-SBSubscription -TopicPath $topicName -Name $subscriptionName -LockDuration 300;
				
				# Arrange Receive Sessions
				$jobString = '{0} -Path "{1}" -WaitTimeoutSec {2} -Receivemode "{3}"' -f $pathMessageHelper, $subscriptionPaths[$i-1], $WaitTimeoutSec, $receiveMode;
				$jobString = [Scriptblock]::Create("1.."+$receiveCyclesPerReceiver+" | % {"+$jobString+"}")
				# write-host $jobString;
				$jobStart = Start-Job -ScriptBlock $jobString;
				$newJobs.Add($jobStart);
			}
			
			# Arrange MessageSender
			$messageSenders = New-Object System.Collections.ArrayList;
			for ($i=1; $i -le $amountMessageSender; $i++) 
			{
				$messageSenderNew = Get-SBMessageSender -Facility $topicName;
				$messageSenders.Add($messageSenderNew);
			}
			##########################################################
			# Act
			##########################################################
			# Send Message
			$messageIds = New-Object System.Collections.ArrayList;
			for ($i=1; $i -le $messageAmount; $i++) 
			{
				if ($numberOfSender -eq $amountMessageSender) 
				{
					$numberOfSender = 0;
				} 
				else 
				{
					$numberOfSender++;
				}
				$messageIdNew = New-SBMessage $messageText -Facility $topicName -MessageClient $messageSenders[$numberOfSender-1];
				$messageIds.Add($messageIdNew);
			}
			##########################################################
			# Assert
			##########################################################
			# Get subscriptions
			$getSubscriptions = Get-SBSubscriptions -TopicPath $topicName
			
			$getSubscriptions.count | Should Be $amountOfReceiver;
			$messageSenders.count | Should Be $amountMessageSender;
			$newJobs.count | Should Be $amountOfReceiver;
			
			# Check subscriptions message count / every subscription has all messages
			foreach ($subscription in $getSubscriptions) 
			{
				$subscription.MessageCount | Should Be $messageAmount;
			}
			
			# Waite till all jobs are done
			$null = Wait-Job -Job $newJobs;
			
			# Get results (Messages) per Job
			foreach ($job in $newJobs)
			{
				$jobResults = Receive-Job $job;
				
				# Assert message per receiver
					# if amount of message is greater than receive cycles then the receiver should have same amount of massages as receive cycles
					# if amount of message is lesser than receive cycles - receiver should have same amount of messages as amount of send messages
				if ($receiveCyclesPerReceiver -ge $messageAmount) 
				{
					($jobResults | where { $_ -ne $null }).count | Should Be $messageAmount;
				} 
				else 
				{
					$jobResults.count | Should Be $receiveCyclesPerReceiver;
				}
				
				# Get Message
				foreach ($resultMessage in ($jobResults | where { $_ -ne $null })) 
				{
					# Assert MessageId (send and receive)
					$messageIds -contains $resultMessage.MessageId | Should be $true;
				}
			}
			##########################################################
			# Cleanup
			##########################################################
			Remove-Job $newJobs;
		}
		
		It "SBClientBroadcast-SendAndAllRecipientsReceiveMessages" -Test {
			<# 
				GIVEN there are multiple senders S1 and S2
				  AND there is a message sink MS1
				  AND this sink is in *BROADCAST* mode
				  AND this sink has multiple subscription SUB1, SUB2, SUB3
				  AND there are multiple receivers R1, R2, R3
				WHEN R1 subscript to SUB1
				  AND R2 subscript to SUB2
				  AND R3 subscribe to SUB3
				  AND S1 sends messages M10, M11, M14
				  AND S2 send messages M12, M13, M15
				  AND the number of the messages indicates the sequence in which they are sent
				THEN every message is delivered exactly one time to each of the receivers
				  AND all receivers receive all message
			#>
		
			##########################################################
			# Arrange
			##########################################################
			$pathMessageHelper = "$here\getMessageHelper.ps1"

			# Arrange test parameter
			$receiveMode = 'ReceiveAndDelete';
			$waitTimeoutSec = 10;
			$amountOfReceiver = 3;
			$receiveCyclesPerReceiver = 10;
			$amountMessageSender = 2;
			$messageAmount = 6;
			$numberOfSender = 3;
			$messageText = "TestMessageBroadcast"
			
			# Arrange MessageReceiver (separate sessions)
			$newJobs = New-Object System.Collections.ArrayList
			$subscriptionPaths = New-Object System.Collections.ArrayList;
			$guid = [guid]::NewGuid().ToString();

			for ($i=1; $i -le $amountOfReceiver; $i++)
			{
				# Arrange Subscriptions
				$subscriptionName = 'Pester-{0}-{1}' -f $guid, $i;
				$subscriptionPath = "{0}\Subscriptions\{1}" -f $topicName, $subscriptionName;
				$subscriptionPaths.Add($subscriptionPath);
				New-SBSubscription -TopicPath $topicName -Name $subscriptionName -LockDuration 300;
			}
			
			# Arrange MessageSender
			$messageSenders = New-Object System.Collections.ArrayList;
			for ($i=1; $i -le $amountMessageSender; $i++) 
			{
				$messageSenderNew = Get-SBMessageSender -Facility $topicName;
				$messageSenders.Add($messageSenderNew);
			}
			##########################################################
			# Act
			##########################################################
			# Send Message
			$messageIds = New-Object System.Collections.ArrayList;
			for ($i=1; $i -le $messageAmount; $i++) 
			{
				if ($numberOfSender -eq $amountMessageSender) 
				{
					$numberOfSender = 1;
				} 
				else 
				{
					$numberOfSender++;
				}
				$messageIdNew = New-SBMessage $messageText -Facility $topicName -MessageClient $messageSenders[$numberOfSender-1];
				$messageIds.Add($messageIdNew);
			}
			
			# Get subscribtion after send
			$getSubscriptions = Get-SBSubscriptions -TopicPath $topicName;
			
			# Receive Message
			for ($i=1; $i -le $amountOfReceiver; $i++)
			{
				# Get Subscription
				$subscriptionName = 'Pester-{0}-{1}' -f $guid, $i;
				$subscriptionPath = "{0}\Subscriptions\{1}" -f $topicName, $subscriptionName;
				
				# Receive Sessions
				$jobString = '{0} -Path "{1}" -WaitTimeoutSec {2} -Receivemode "{3}"' -f $pathMessageHelper, $subscriptionPath, $WaitTimeoutSec, $receiveMode;
				$jobString = [Scriptblock]::Create("1.."+$receiveCyclesPerReceiver+" | % {"+$jobString+"}")
				# write-host $jobString;
				$jobStart = Start-Job -ScriptBlock $jobString;
				$newJobs.Add($jobStart);
			}
			
			##########################################################
			# Assert
			##########################################################
			
			# Assert subscriptions			
			$getSubscriptions.count | Should Be $amountOfReceiver;
			$messageSenders.count | Should Be $amountMessageSender;
			$newJobs.count | Should Be $amountOfReceiver;
			
			# Check subscriptions message count / every subscription has all messages
			foreach ($subscription in $getSubscriptions) 
			{
				$subscription.MessageCount | Should Be $messageAmount;
			}
			
			# Waite till all jobs are done
			$null = Wait-Job -Job $newJobs;
			
			# Get results (Messages) per Job
			foreach ($job in $newJobs)
			{
				$jobResults = Receive-Job $job;
				
				# Assert message per receiver
					# if amount of message is greater than receive cycles then the receiver should have same amount of massages as receive cycles
					# if amount of message is lesser than receive cycles - receiver should have same amount of messages as amount of send messages
				if ($receiveCyclesPerReceiver -ge $messageAmount) 
				{
					($jobResults | where { $_ -ne $null }).count | Should Be $messageAmount;
				} 
				else 
				{
					$jobResults.count | Should Be $receiveCyclesPerReceiver;
				}
				
				# Get Message
				foreach ($resultMessage in ($jobResults | where { $_ -ne $null })) 
				{
					# Assert MessageId (send and receive)
					$messageIds -contains $resultMessage.MessageId | Should be $true;
				}
			}
			
			# Get subscribtion after receive
			$getSubscriptionsAfterRecv = Get-SBSubscriptions -TopicPath $topicName;
			
			# Check subscriptions message count / every subscription has all messages
			foreach ($subscription in $getSubscriptionsAfterRecv) 
			{
				$subscription.MessageCount | Should Be 0;
			}
			
			##########################################################
			# Cleanup
			##########################################################
			Remove-Job $newJobs;
		}
		
		It "SBClientBroadcast-SendMessagesAndAllRecipientsSubscribe" -Test {
			<# 
				GIVEN there are multiple senders S1 and S2
				  AND there is a message sink MS1
				  AND this sink is in *BROADCAST* mode
				  AND this sink has multiple subscription SUB1, SUB2, SUB3
				  AND there are multiple receivers R1, R2, R3
				WHEN R1 subscript to SUB1
				  AND R2 subscript to SUB2
				  AND R3 subscribe to SUB3
				  AND S1 sends messages M10, M11, M14
				  AND S2 send messages M12, M13, M15
				  AND the number of the messages indicates the sequence in which they are sent
				THEN every message is delivered exactly one time to each of the receivers
				  AND it the receivers do not acknowledge message receipt
			#>
		
			##########################################################
			# Arrange
			##########################################################
			$pathMessageHelper = "$here\getMessageHelper.ps1"

			# Arrange test parameter
			$receiveMode = 'ReceiveAndDelete';
			$waitTimeoutSec = 10;
			$amountOfReceiver = 3;
			$receiveCyclesPerReceiver = 10;
			$amountMessageSender = 2;
			$messageAmount = 6;
			$numberOfSender = 2;
			$messageText = "TestMessageBroadcast"
			
			# Arrange MessageReceiver (separate sessions)
			$subscriptionPaths = New-Object System.Collections.ArrayList;
			$guid = [guid]::NewGuid().ToString();

			for ($i=1; $i -le $amountOfReceiver; $i++)
			{
				# Arrange Subscriptions
				$subscriptionName = 'Pester-{0}-{1}' -f $guid, $i;
				$subscriptionPath = "{0}\Subscriptions\{1}" -f $topicName, $subscriptionName;
				$subscriptionPaths.Add($subscriptionPath);
				New-SBSubscription -TopicPath $topicName -Name $subscriptionName -LockDuration 300;
			}
			
			# Arrange MessageSender
			$messageSenders = New-Object System.Collections.ArrayList;
			for ($i=1; $i -le $amountMessageSender; $i++) 
			{
				$messageSenderNew = Get-SBMessageSender -Facility $topicName;
				$messageSenders.Add($messageSenderNew);
			}
			##########################################################
			# Act
			##########################################################
			# Send Message
			$messageIds = New-Object System.Collections.ArrayList;
			for ($i=1; $i -le $messageAmount; $i++) 
			{
				if ($numberOfSender -eq $amountMessageSender) 
				{
					$numberOfSender = 1;
				} 
				else 
				{
					$numberOfSender++;
				}
				$messageIdNew = New-SBMessage $messageText -Facility $topicName -MessageClient $messageSenders[$numberOfSender-1];
				$messageIds.Add($messageIdNew);
			}
			
			# Get subscribtion after send
			$getSubscriptions = Get-SBSubscriptions -TopicPath $topicName;
			

			##########################################################
			# Assert
			##########################################################
			
			# Assert subscriptions			
			$getSubscriptions.count | Should Be $amountOfReceiver;
			$messageSenders.count | Should Be $amountMessageSender;
			
			# Check subscriptions message count / every subscription has all messages
			foreach ($subscription in $getSubscriptions) 
			{
				$subscription.MessageCount | Should Be $messageAmount;
			}
			
			##########################################################
			# Cleanup
			##########################################################

		}
		
		It "SBClientBroadcast-SendToSubscriptionFail" -Test {
			<# 
				GIVEN there is a sink MS1
				  AND this sink is in *BROADCAST* mode
				  AND this sink has a subscription SUB1
				  AND there is a sender S1
				WHEN S1 send a message to subscription SUB1
				THEN S1 get an exception
			#>
		
			##########################################################
			# Arrange
			##########################################################
			# Arrange Subscriptions
			$guid = [guid]::NewGuid().ToString();
			$subscriptionName = 'Pester-{0}-{1}' -f $guid, 1;
			$subscriptionPath = "{0}\Subscriptions\{1}" -f $topicName, $subscriptionName;
			$messageText = "TestMessageBroadcast"
			
			##########################################################
			# Act
			##########################################################
			# Try send a message to a subscription
			$exception = $null;
			try 
			{
				$messageIdNew = New-SBMessage $messageText -Facility $subscriptionPath -Debug -Retry 1;
			}
			catch 
			{
				$exception = $_.Exception;
			}
			
			
			##########################################################
			# Assert
			##########################################################
			$exception | Should be (!$null);
			
			##########################################################
			# Cleanup
			##########################################################

		}
	}
}

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

# SIG # Begin signature block
# MIIXDwYJKoZIhvcNAQcCoIIXADCCFvwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU1zn0qcTmP53MgZxlzEGd3Wjs
# cAigghHCMIIEFDCCAvygAwIBAgILBAAAAAABL07hUtcwDQYJKoZIhvcNAQEFBQAw
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
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBStNvygONJ9+Rs7
# XSfpbxoC6z0TBDANBgkqhkiG9w0BAQEFAASCAQDEYqpJoXVbvQwoBQJdSZtIdO8L
# 8ninDjnw/8/xhqkJM+QqP90LGmdyUWY42lj387c+p5hA/TMXMMCFE4AE8VtzHOVB
# ltqtoaNj0vLBGbK6UMOErzVn9tBivYoaTR4ghNBTQZPevHkSTodMoJGxF5LlR882
# Qdz1ZLlZZZ/+4wB0VLM/q59IaQH8b2p9QHL2sniiZPh8NrMaFFOpQiNUsVIZbT5X
# 2tB6bbkz7I1N5R8X/lRlO0BpDQk+PXTZk7o7+WKaMCJ5zDS9fGUGEVOt9hjxhDml
# dVTSnPBem++YBhrFWiRKLrCJ/Sm/ig5ng96YSqhEVroloxYKhtr4i5/3mjGSoYIC
# ojCCAp4GCSqGSIb3DQEJBjGCAo8wggKLAgEBMGgwUjELMAkGA1UEBhMCQkUxGTAX
# BgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExKDAmBgNVBAMTH0dsb2JhbFNpZ24gVGlt
# ZXN0YW1waW5nIENBIC0gRzICEhEhBqCB0z/YeuWCTMFrUglOAzAJBgUrDgMCGgUA
# oIH9MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1
# MTIxNTE2NTIwM1owIwYJKoZIhvcNAQkEMRYEFA22JKpz3qvRILDPruWvwWYGcoDd
# MIGdBgsqhkiG9w0BCRACDDGBjTCBijCBhzCBhAQUs2MItNTN7U/PvWa5Vfrjv7Es
# KeYwbDBWpFQwUjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYt
# c2ExKDAmBgNVBAMTH0dsb2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0gRzICEhEh
# BqCB0z/YeuWCTMFrUglOAzANBgkqhkiG9w0BAQEFAASCAQBLbX9cgb8WBfyFZCY3
# OAwS8v0mBfpkPoFVNsl5XXr4hERivapSMHrmVDH/nXYPqmp6NjM7mvQWAyh+4rkE
# B4X9dsJvqjHitrDkHw/bISxHf3XYj89R/YCUJu+S+d7m4FiZzxd0DlEnhbypDm7T
# 7Y5NPDU2LVe8kYIVpFTkCOBsMY/z9IP5+njygnAHihVSxGJLc0ptbc3nPNRiuMzD
# Xq+8MhJtRyHxvv8FntbIGp3wQSDjauzB7Sa59Xr6n/fSNCiPQkt9hDlo+6Famv+F
# OnYRgRw2tWPDJnVXdK5BnelGvlq6zXt7puj2/Pd/lAsBvcZPFUjfVY1/SqQcJ16N
# EJpA
# SIG # End signature block
