/////////////////////////////////////////////////////////////////////////
// Copyright (c) 2010 RightScale Inc
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
/////////////////////////////////////////////////////////////////////////
using System;
using System.Collections;
using System.Management.Automation;
using RightScale.Common.Protocol;
using RightScale.Chef.Protocol;
using RightScale.Powershell.Exceptions;

namespace RightScale
{
    namespace Powershell
    {
        namespace Commands
        {
            [Cmdlet(VerbsCommon.Set, "ChefNode")]
            [CmdletBinding(DefaultParameterSetName = "StringParameterSetName")]
            public class SetChefNodeCommand : Cmdlet
            {
                [Parameter(ValueFromPipeline = true, Position = 0, Mandatory=true)]
                public string[] Path
                {
                    get { return path; }
                    set { path = value; }
                }

                [Parameter(ValueFromPipeline = true, Position = 1, ParameterSetName = "StringParameterSetName")]
                public String StringValue
                {
                    get { return (nodeValue is String) ? (String)nodeValue : default(String); }
                    set { nodeValue = value; }
                }

                [Parameter(ValueFromPipeline = true, Position = 1, ParameterSetName = "Int32ParameterSetName")]
                public Int32 Int32Value
                {
                    get { return (nodeValue is Int32) ? (Int32)nodeValue : default(Int32); }
                    set { nodeValue = value; }
                }

                [Parameter(ParameterSetName = "Int64ParameterSetName")]
                public Int64 Int64Value
                {
                    get { return (nodeValue is Int64) ? (Int64)nodeValue : default(Int64); }
                    set { nodeValue = value; }
                }

                [Parameter(ParameterSetName = "HashValueSetName")]
                public IDictionary HashValue
                {
                    get { return (nodeValue is IDictionary) ? (IDictionary)nodeValue : default(IDictionary); }
                    set { nodeValue = value; }
                }

                [Parameter(ParameterSetName = "DoubleParameterSetName")]
                public Double DoubleValue
                {
                    get { return (nodeValue is Double) ? (Double)nodeValue : default(Double); }
                    set { nodeValue = value; }
                }

                [Parameter(ParameterSetName = "ArrayParameterSetName")]
                public Array ArrayValue
                {
                    get { return (nodeValue is Array) ? (Array)nodeValue : default(Array); }
                    set { nodeValue = value; }
                }

                [Parameter(ParameterSetName = "BooleanParameterSetName")]
                public Boolean BooleanValue
                {
                    get { return (nodeValue is Boolean) ? (Boolean)nodeValue : default(Boolean); }
                    set { nodeValue = value; }
                }

                [Parameter(ParameterSetName = "NullParameterSetName")]
                public SwitchParameter NullValue
                {
                    get { return null == nodeValue; }
                    set { nodeValue = null; }
                }

                protected override void ProcessRecord()
                {
                    ITransport transport = new JsonTransport();
                    PipeClient pipeClient = new PipeClient(Constants.CHEF_NODE_PIPE_NAME, transport);

                    try
                    {
                        pipeClient.Connect(Constants.CHEF_NODE_CONNECT_TIMEOUT_MSECS);

                        SetChefNodeRequest request = null;

                        request = new SetChefNodeRequest(path, ConvertValue(nodeValue));

                        IDictionary responseHash = (IDictionary)transport.NormalizeDeserializedObject(pipeClient.SendReceive<object>(request));

                        if (null == responseHash)
                        {
                            throw new ChefNodeCmdletException("Failed to get expected response.");
                        }
                        if (ChefNodeCmdletException.HasError(responseHash))
                        {
                            throw new ChefNodeCmdletException(responseHash);
                        }
                    }
                    catch (TimeoutException e)
                    {
                        ThrowTerminatingError(new ErrorRecord(e, "Connection timed out", ErrorCategory.OperationTimeout, pipeClient));
                    }
                    catch (Exception e)
                    {
                        ThrowTerminatingError(new ErrorRecord(e, "Unexpected exception", ErrorCategory.NotSpecified, pipeClient));
                    }
                    finally
                    {
                        pipeClient.Close();
                        pipeClient = null;
                    }
                }

                // Summary:
                //  converts a node value from powershell-specific types to a marshalable type.
                //
                // Parameters:
                //   value:
                //      raw powershell value which may or may not be a marshalable type.
                //
                // Returns:
                //  value as a marshalable type
                private object ConvertValue(object rawValue)
                {
                    if (null == rawValue)
                    {
                        return null;
                    }
                    if (rawValue is PSObject)
                    {
                        PSObject pso = (PSObject)rawValue;

                        return ConvertValue(pso.BaseObject);
                    }
                    if (rawValue is Array)
                    {
                        return ConvertArrayValue((Array)rawValue);
                    }
                    if (rawValue is IDictionary)
                    {
                        return ConvertHashValue((IDictionary)rawValue);
                    }
                    if (Array.IndexOf(SUPPORTED_PRIMITIVES, rawValue.GetType()) > 0)
                    {
                        return rawValue;
                    }

                    // note that some types are infinitely serializable, which leads to stack overflow.
                    // the transport layer may or may not fail for circular references (depending on
                    // implementation) but there are many types of infinitely serializable objects.
                    // an example is FileInfo, which contains a DirectoryInfo for it's parent directory
                    // which, when serialized, produces the same listing containing the FileInfo which
                    // contains the same DirectoryInfo, ad infinitum.
                    //
                    // FIX: attempt to convert the object to a hash of primitive types and otherwise
                    // call .ToString() on any non-primitive members. the type of the original object
                    // is lost but duck typing is assumed (per JSON standard).
                    return rawValue.ToString();
                }

                // Summary:
                //  converts an array containing one or more powershell-specific objects to marshalable array.
                //
                // Parameters:
                //   arrayValue:
                //      array to convert.
                //
                // Returns:
                //  array containing marshalable values.
                private object ConvertArrayValue(Array arrayValue)
                {
                    ArrayList copyArray = new ArrayList(arrayValue.Length);

                    foreach (object value in arrayValue)
                    {
                        copyArray.Add(ConvertValue(value));
                    }

                    return copyArray;
                }

                // Summary:
                //  converts a hash containing one or more powershell-specific objects to marshalable array.
                //
                // Parameters:
                //   hashValue:
                //      hash to convert.
                //
                // Returns:
                //  hash containing marshalable values.
                private object ConvertHashValue(IDictionary hashValue)
                {
                    IDictionary copyHash = new Hashtable();

                    foreach (object key in hashValue.Keys)
                    {
                        object copyKey = ConvertValue(key);
                        object copyValue = ConvertValue(hashValue[key]);

                        copyHash.Add(copyKey, copyValue);
                    }

                    return copyHash;
                }

                static private Type[] SUPPORTED_PRIMITIVES = new Type[] { typeof(String), typeof(Int32), typeof(Int64), typeof(Double), typeof(Boolean) };

                private string[] path;
                private object nodeValue;
            }
        }
    }
}
