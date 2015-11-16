$fn = $MyInvocation.MyCommand.Name;

Set-Variable gotoSuccess -Option 'Constant' -Value 'biz.dfch.System.Exception.gotoSuccess';
Set-Variable gotoError -Option 'Constant' -Value 'biz.dfch.System.Exception.gotoError';
Set-Variable gotoFailure -Option 'Constant' -Value 'biz.dfch.System.Exception.gotoFailure';
Set-Variable gotoNotFound -Option 'Constant' -Value 'biz.dfch.System.Exception.gotoNotFound';

[string] $ModuleConfigFile = '{0}.xml' -f (Get-Item $PSCommandPath).BaseName;
[string] $ModuleConfigurationPathAndFile = Join-Path -Path $PSScriptRoot -ChildPath $ModuleConfigFile;
$mvar = $ModuleConfigFile.Replace('.xml', '').Replace('.', '_');
if($true -eq (Test-Path -Path $ModuleConfigurationPathAndFile)) 
{
	if($true -ne (Test-Path variable:$($mvar))) 
	{
		Log-Debug $fn ("Loading module configuration file from: '{0}' ..." -f $ModuleConfigurationPathAndFile);
		Set-Variable -Name $mvar -Value (Import-Clixml -Path $ModuleConfigurationPathAndFile);
	}
}

if($true -ne (Test-Path variable:$($mvar))) 
{
	Write-Error "Could not find module configuration file '$ModuleConfigFile' in 'ENV:PSModulePath'.`nAborting module import...";
	# Aborts loading module.
	break;
}

Export-ModuleMember -Variable $mvar;

[string] $ManifestFile = '{0}.psd1' -f (Get-Item $PSCommandPath).BaseName;
$ManifestPathAndFile = Join-Path -Path $PSScriptRoot -ChildPath $ManifestFile;
if(Test-Path -Path $ManifestPathAndFile)
{
	$Manifest = (Get-Content -raw $ManifestPathAndFile) | iex;
	foreach( $ScriptToProcess in $Manifest.ScriptsToProcess) 
	{ 
		$ModuleToRemove = (Get-Item (Join-Path -Path $PSScriptRoot -ChildPath $ScriptToProcess)).BaseName;
		if(Get-Module $ModuleToRemove)
		{ 
			Remove-Module $ModuleToRemove -ErrorAction:SilentlyContinue;
		}
	}
}

(Get-Variable -Name $mvar).Value.Credential = [System.Net.CredentialCache]::DefaultCredentials;

function Invoke-GenericMethod
{
    <#
    .Synopsis
       Invokes Generic methods on .NET Framework types
    .DESCRIPTION
       Allows the caller to invoke a Generic method on a .NET object or class with a single function call.  Invoke-GenericMethod handles identifying the proper method overload, parameters with default values, and to some extent, the same type conversion behavior you expect when calling a normal .NET Framework method from PowerShell.
    .PARAMETER InputObject
       The object on which to invoke an instance generic method.
    .PARAMETER Type
       The .NET class on which to invoke a static generic method.
    .PARAMETER MethodName
       The name of the generic method to be invoked.
    .PARAMETER GenericType
       One or more types which are specified when calling the generic method.  For example, if a method's signature is "string MethodName<T>();", and you want T to be a String, then you would pass "string" or ([string]) to the Type parameter of Invoke-GenericMethod.
    .PARAMETER ArgumentList
       The arguments to be passed on to the generic method when it is invoked.  The order of the arguments must match that of the .NET method's signature; named parameters are not currently supported.
    .EXAMPLE
       Invoke-GenericMethod -InputObject $someObject -MethodName SomeMethodName -GenericType string -ArgumentList $arg1,$arg2,$arg3

       Invokes a generic method on an object.  The signature of this method would be something like this (containing 3 arguments and a single Generic type argument):  object SomeMethodName<T>(object arg1, object arg2, object arg3);
    .EXAMPLE
       $someObject | Invoke-GenericMethod -MethodName SomeMethodName -GenericType string -ArgumentList $arg1,$arg2,$arg3

       Same as example 1, except $someObject is passed to the function via the pipeline.
    .EXAMPLE
       Invoke-GenericMethod -Type SomeClass -MethodName SomeMethodName -GenericType string,int -ArgumentList $arg1,$arg2,$arg3

       Invokes a static generic method on a class.  The signature of this method would be something like this (containing 3 arguments and two Generic type arguments):  static object SomeMethodName<T1,T2> (object arg1, object arg2, object arg3);
    .INPUTS
       System.Object
    .OUTPUTS
       System.Object
    .NOTES
       Known issues:

       Ref / Out parameters and [PSReference] objects are currently not working properly, and I don't think there's a way to fix that from within PowerShell.  I'll have to expand on the
       PSGenericTypes.MethodInvoker.InvokeMethod() C# code to account for that.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Instance')]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Instance')]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'Static')]
        [Type]
        $Type,

        [Parameter(Mandatory = $true)]
        [string]
        $MethodName,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $GenericType,

        [Object[]]
        $ArgumentList
    )

    process
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            'Instance'
            {
                $_type  = $InputObject.GetType()
                $object = $InputObject
                $flags  = [System.Reflection.BindingFlags] 'Instance, Public'
            }

            'Static'
            {
                $_type  = $Type
                $object = $null
                $flags  = [System.Reflection.BindingFlags] 'Static, Public'
            }
        }

        if ($null -ne $ArgumentList)
        {
            $argList = $ArgumentList.Clone()
        }
        else
        {
            $argList = @()
        }

        $params = @{
            Type         = $_type
            BindingFlags = $flags
            MethodName   = $MethodName
            GenericType  = $GenericType
            ArgumentList = [ref]$argList
        }

        $method = Get-GenericMethod @params

        if ($null -eq $method)
        {
            Write-Error "No matching method was found"
            return
        }

        # I'm not sure why, but PowerShell appears to be passing instances of PSObject when $argList contains generic types.  Instead of calling
        # $method.Invoke here from PowerShell, I had to write the PSGenericMethods.MethodInvoker.InvokeMethod helper code in C# to enumerate the
        # argument list and replace any instances of PSObject with their BaseObject before calling $method.Invoke().

        return [PSGenericMethods.MethodInvoker]::InvokeMethod($method, $object, $argList)

    } # process

} # function Invoke-GenericMethod

function Get-GenericMethod
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Type]
        $Type,

        [Parameter(Mandatory = $true)]
        [string]
        $MethodName,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $GenericType,

        [ref]
        $ArgumentList,

        [System.Reflection.BindingFlags]
        $BindingFlags = [System.Reflection.BindingFlags]::Default,

        [switch]
        $WithCoercion
    )

    if ($null -eq $ArgumentList.Value)
    {
        $originalArgList = @()
    }
    else
    {
        $originalArgList = @($ArgumentList.Value)
    }

    foreach ($method in $Type.GetMethods($BindingFlags))
    {
        $argList = $originalArgList.Clone()

        if (-not $method.IsGenericMethod -or $method.Name -ne $MethodName) { continue }
        if ($GenericType.Count -ne $method.GetGenericArguments().Count) { continue }

        if (Test-GenericMethodParameters -MethodInfo $method -ArgumentList ([ref]$argList) -GenericType $GenericType -WithCoercion:$WithCoercion)
        {
            $ArgumentList.Value = $argList
            return $method.MakeGenericMethod($GenericType)
        }
    }

    if (-not $WithCoercion)
    {
        $null = $PSBoundParameters.Remove('WithCoercion')
        return Get-GenericMethod @PSBoundParameters -WithCoercion
    }

} # function Get-GenericMethod

function Test-GenericMethodParameters
{
    [CmdletBinding()]
    param (
        [System.Reflection.MethodInfo] $MethodInfo,

        [ref]
        $ArgumentList,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $GenericType,

        [switch]
        $WithCoercion
    )

    if ($null -eq $ArgumentList.Value)
    {
        $argList = @()
    }
    else
    {
        $argList = @($ArgumentList.Value)
    }

    $parameterList = $MethodInfo.GetParameters()

    $arrayType = $null

    $hasParamsArray = HasParamsArray -ParameterList $parameterList

    if ($parameterList.Count -lt $argList.Count -and -not $hasParamsArray)
    {
        return $false
    }

    $methodGenericType = $MethodInfo.GetGenericArguments()

    for ($i = 0; $i -lt $argList.Count; $i++)
    {
        $params = @{
            ArgumentList       = $argList
            ParameterList      = $ParameterList
            WithCoercion       = $WithCoercion
            RuntimeGenericType = $GenericType
            MethodGenericType  = $methodGenericType
            Index              = [ref]$i
            ArrayType          = [ref]$arrayType
        }

        $isOk = TryMatchParameter @params

        if (-not $isOk) { return $false }
    }

    $defaults = New-Object System.Collections.ArrayList

    for ($i = $argList.Count; $i -lt $parameterList.Count; $i++)
    {
        if (-not $parameterList[$i].HasDefaultValue)  { return $false }
        $null = $defaults.Add($parameterList[$i].DefaultValue)
    }

    # When calling a method with a params array using MethodInfo, you have to pass in the array; the
    # params argument approach doesn't work.

    if ($hasParamsArray)
    {
        $firstArrayIndex = $parameterList.Count - 1
        $lastArrayIndex = $argList.Count - 1

        $newArgList = $argList[0..$firstArrayIndex]
        $newArgList[$firstArrayIndex] = $argList[$firstArrayIndex..$lastArrayIndex] -as $arrayType
        $argList = $newArgList
    }

    $ArgumentList.Value = $argList + $defaults.ToArray()

    return $true

} # function Test-GenericMethodParameters

function TryMatchParameter
{
    param (
        [System.Reflection.ParameterInfo[]]
        $ParameterList,

        [object[]]
        $ArgumentList,

        [Type[]]
        $MethodGenericType,

        [Type[]]
        $RuntimeGenericType,

        [switch]
        $WithCoercion,

        [ref] $Index,
        [ref] $ArrayType
    )

    $params = @{
        ParameterType = $ParameterList[$Index.Value].ParameterType
        RuntimeType   = $RuntimeGenericType
        GenericType   = $MethodGenericType
    }

    $runtimeType = Resolve-RuntimeType @params

    if ($null -eq $runtimeType)
    {
        throw "Could not determine runtime type of parameter '$($ParameterList[$Index.Value].Name)'"
    }

    $isParamsArray = IsParamsArray -ParameterInfo $ParameterList[$Index.Value]

    if ($isParamsArray)
    {
        $ArrayType.Value = $runtimeType
        $runtimeType     = $runtimeType.GetElementType()
    }

    do
    {
        $isOk = TryMatchArgument @PSBoundParameters -RuntimeType $runtimeType
        if (-not $isOk) { return $false }

        if ($isParamsArray) { $Index.Value++ }
    }
    while ($isParamsArray -and $Index.Value -lt $ArgumentList.Count)

    return $true
}

function TryMatchArgument
{
    param (
        [System.Reflection.ParameterInfo[]]
        $ParameterList,

        [object[]]
        $ArgumentList,

        [Type[]]
        $MethodGenericType,

        [Type[]]
        $RuntimeGenericType,

        [switch]
        $WithCoercion,

        [ref] $Index,
        [ref] $ArrayType,

        [Type] $RuntimeType
    )

    $argValue = $ArgumentList[$Index.Value]
    $argType = Get-Type $argValue

    $isByRef = $RuntimeType.IsByRef
    if ($isByRef)
    {
        if ($ArgumentList[$Index.Value] -isnot [ref]) { return $false }

        $RuntimeType = $RuntimeType.GetElementType()
        $argValue = $argValue.Value
        $argType = Get-Type $argValue
    }

    $isNullNullable = $false

    while ($RuntimeType.FullName -like 'System.Nullable``1*')
    {
        if ($null -eq $argValue)
        {
            $isNullNullable = $true
            break
        }

        $RuntimeType = $RuntimeType.GetGenericArguments()[0]
    }

    if ($isNullNullable) { continue }

    if ($null -eq $argValue)
    {
        return -not $RuntimeType.IsValueType
    }
    else
    {
        if ($argType -ne $RuntimeType)
        {
            $argValue = $argValue -as $RuntimeType
            if (-not $WithCoercion -or $null -eq $argValue)  { return $false }
        }

        if ($isByRef)
        {
            $ArgumentList[$Index.Value].Value = $argValue
        }
        else
        {
            $ArgumentList[$Index.Value] = $argValue
        }
    }

    return $true
}
function HasParamsArray([System.Reflection.ParameterInfo[]] $ParameterList)
{
    return $ParameterList.Count -gt 0 -and (IsParamsArray -ParameterInfo $ParameterList[-1])
}

function IsParamsArray([System.Reflection.ParameterInfo] $ParameterInfo)
{
    return @($ParameterInfo.GetCustomAttributes([System.ParamArrayAttribute], $true)).Count -gt 0
}

function Resolve-RuntimeType
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Type]
        $ParameterType,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $RuntimeType,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $GenericType
    )

    if ($ParameterType.IsByRef)
    {
        $elementType = Resolve-RuntimeType -ParameterType $ParameterType.GetElementType() -RuntimeType $RuntimeType -GenericType $GenericType
        return $elementType.MakeByRefType()
    }
    elseif ($ParameterType.IsGenericParameter)
    {
        for ($i = 0; $i -lt $GenericType.Count; $i++)
        {
            if ($ParameterType -eq $GenericType[$i])
            {
                return $RuntimeType[$i]
            }
        }
    }
    elseif ($ParameterType.IsArray)
    {
        $arrayType = $ParameterType
        $elementType = Resolve-RuntimeType -ParameterType $ParameterType.GetElementType() -RuntimeType $RuntimeType -GenericType $GenericType

        if ($ParameterType.GetElementType().IsGenericParameter)
        {
            $arrayRank = $arrayType.GetArrayRank()

            if ($arrayRank -eq 1)
            {
                $arrayType = $elementType.MakeArrayType()
            }
            else
            {
                $arrayType = $elementType.MakeArrayType($arrayRank)
            }
        }

        return $arrayType
    }
    elseif ($ParameterType.ContainsGenericParameters)
    {
        $genericArguments = $ParameterType.GetGenericArguments()
        $runtimeArguments = New-Object System.Collections.ArrayList

        foreach ($argument in $genericArguments)
        {
            $null = $runtimeArguments.Add((Resolve-RuntimeType -ParameterType $argument -RuntimeType $RuntimeType -GenericType $GenericType))
        }

        $definition = $ParameterType
        if (-not $definition.IsGenericTypeDefinition)
        {
            $definition = $definition.GetGenericTypeDefinition()
        }

        return $definition.MakeGenericType($runtimeArguments.ToArray())
    }
    else
    {
        return $ParameterType
    }
}

function Get-Type($object)
{
    if ($null -eq $object) { return $null }
    return $object.GetType()
}

Add-Type -ErrorAction Stop -TypeDefinition @'
    namespace PSGenericMethods
    {
        using System;
        using System.Reflection;
        using System.Management.Automation;

        public static class MethodInvoker
        {
            public static object InvokeMethod(MethodInfo method, object target, object[] arguments)
            {
                if (method == null) { throw new ArgumentNullException("method"); }

                object[] args = null;

                if (arguments != null)
                {
                    args = (object[])arguments.Clone();
                    for (int i = 0; i < args.Length; i++)
                    {
                        PSObject pso = args[i] as PSObject;
                        if (pso != null)
                        {
                            args[i] = pso.BaseObject;
                        }

                        PSReference psref = args[i] as PSReference;

                        if (psref != null)
                        {
                            args[i] = psref.Value;
                        }
                    }
                }

                object result = method.Invoke(target, args);

                for (int i = 0; i < arguments.Length; i++)
                {
                    PSReference psref = arguments[i] as PSReference;

                    if (psref != null)
                    {
                        psref.Value = args[i];
                    }
                }

                return result;
            }
        }
    }
'@
Export-ModuleMember -Function 'Invoke-GenericMethod'

# 
# Copyright 2014-2015 Ronald Rink, d-fens GmbH
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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUTY6iGw3Cqkz7i4Mz25CEr+7t
# 7yqgghHCMIIEFDCCAvygAwIBAgILBAAAAAABL07hUtcwDQYJKoZIhvcNAQEFBQAw
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
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQ8yuDs2QFBnYcC
# iKSzKualu9NFrjANBgkqhkiG9w0BAQEFAASCAQA21/OGUGt6be4Iwj+QtwmLvq4d
# qBV1r25vmQqTx7WBq/4gaIIfDAdXT7D0EYWmQXqAIxzxvix+AWvwYp6k1K2IdJ7w
# vRU6RLsOvKi3h8X3jewgi7TPd/8RyveHBjUAESQH2S2BLjzPNZm92dmfWzel3RP6
# RYL39dXkX10yjA0rZwnr0Z1Vnwg8a/d5XqK8ujmznnYnIfXGNyOtFZuc25Y4iJ6Q
# VA5UaXulwmI7OnGV3K6zlofPbrOOXgsHCw78eG7LnNoNdKnkKNFFFTcrR18dLEb3
# f6gCKLYPMwYnhQFVUzN9OF9tyc9D89yWMHoC/t+SGDlzvi7yswFl2AjlJhvWoYIC
# ojCCAp4GCSqGSIb3DQEJBjGCAo8wggKLAgEBMGgwUjELMAkGA1UEBhMCQkUxGTAX
# BgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExKDAmBgNVBAMTH0dsb2JhbFNpZ24gVGlt
# ZXN0YW1waW5nIENBIC0gRzICEhEhBqCB0z/YeuWCTMFrUglOAzAJBgUrDgMCGgUA
# oIH9MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1
# MTExNjEwNTg1OVowIwYJKoZIhvcNAQkEMRYEFOzdRRgVjaHvI2QTrgUVs/VN3Q4O
# MIGdBgsqhkiG9w0BCRACDDGBjTCBijCBhzCBhAQUs2MItNTN7U/PvWa5Vfrjv7Es
# KeYwbDBWpFQwUjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYt
# c2ExKDAmBgNVBAMTH0dsb2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0gRzICEhEh
# BqCB0z/YeuWCTMFrUglOAzANBgkqhkiG9w0BAQEFAASCAQBJGaMGM5jdFf70nxIj
# qgruQHpq9ztYGVJffly+g2HcSrThiHf331Uy4TZRQvuGONYzv9bmA/zRq0sKoHJR
# 57F3S60iXQI2teJYFFtCIxmoYgbAveVCsoMbzrLl14M3aKQSfZUQ9SR8V3UUSt7i
# dym9pfvUlVPHRyNHKZxInSFnZvYgK61X43yaKVa0YEo8zqqruDRdd9ufpiLo+qle
# b9hiZzKH4g+QvRjV5GkTeNMRTn2al3fnekz2mKt7mPcXPZshGqaZOy8CMVIhmd13
# Y6POOCSOF3U9VUA5ytzSyzsz0Jtk7+tuTcjRTJnCvqjcTtZPICEnpzZL8V+0vyCV
# YdUh
# SIG # End signature block
