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
using System.Threading;
using RightScale.Common.Protocol;
using RightScale.Chef.Protocol;
using RightScale.Powershell.Exceptions;

namespace RightScale
{
    namespace Powershell
    {
        namespace Commands
        {
            public abstract class SetNodeValueCommandBase : Cmdlet
            {
                [Parameter(ValueFromPipeline = true, Position = 0, Mandatory = true)]
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

                [Parameter(ValueFromPipeline = true, Position = 1, ParameterSetName = "HashValueSetName")]
                public IDictionary HashValue
                {
                    get { return (nodeValue is IDictionary) ? (IDictionary)nodeValue : default(IDictionary); }
                    set { nodeValue = value; }
                }

                [Parameter(ValueFromPipeline = true, Position = 1, ParameterSetName = "BooleanParameterSetName")]
                public Boolean BooleanValue
                {
                    get { return (nodeValue is Boolean) ? (Boolean)nodeValue : default(Boolean); }
                    set { nodeValue = value; }
                }

                [Parameter(ParameterSetName = "Int64ParameterSetName")]
                public Int64 Int64Value
                {
                    get { return (nodeValue is Int64) ? (Int64)nodeValue : default(Int64); }
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

                [Parameter(ParameterSetName = "NullParameterSetName")]
                public SwitchParameter NullValue
                {
                    get { return null == nodeValue; }
                    set { nodeValue = null; }
                }

                // Summary:
                //  Factory method for request from cmdlet parameters.
                //
                // Returns:
                //  request object
                protected abstract SetNodeValueRequestBase CreateRequest();

                // Summary:
                //  Factory method for exception from message.
                //
                // Returns:
                //  exception
                protected abstract ChefNodeCmdletExceptionBase CreateException(string message);

                // Summary:
                //  Factory method for exception from response hash.
                //
                // Returns:
                //  exception
                protected abstract ChefNodeCmdletExceptionBase CreateException(IDictionary responseHash);

                protected override void ProcessRecord()
                {
                    // iterate attempting to connect, send and receive to Chef node server.
                    for (int tryIndex = 0; tryIndex < Constants.MAX_CLIENT_RETRIES; ++tryIndex)
                    {
                        ITransport transport = new JsonTransport();
                        PipeClient pipeClient = new PipeClient(Constants.CHEF_NODE_PIPE_NAME, transport);

                        try
                        {
                            pipeClient.Connect(Constants.CHEF_NODE_CONNECT_TIMEOUT_MSECS);

                            SetNodeValueRequestBase request = CreateRequest();

                            IDictionary responseHash = (IDictionary)transport.NormalizeDeserializedObject(pipeClient.SendReceive<object>(request));

                            if (null == responseHash)
                            {
                                if (tryIndex + 1 < Constants.MAX_CLIENT_RETRIES)
                                {
                                    // delay retry a few ticks to yield time in case server is busy.
                                    Thread.Sleep(Constants.SLEEP_BETWEEN_CLIENT_RETRIES_MSECS);
                                    continue;
                                }
                                else
                                {
                                    string message = String.Format("Failed to get expected response after {0} retries.", Constants.MAX_CLIENT_RETRIES);

                                    throw CreateException(message);
                                }
                            }
                            if (ChefNodeCmdletExceptionBase.HasError(responseHash))
                            {
                                throw CreateException(responseHash);
                            }

                            // done.
                            break;
                        }
                        catch (TimeoutException e)
                        {
                            ThrowTerminatingError(new ErrorRecord(e, "Connection timed out", ErrorCategory.OperationTimeout, pipeClient));
                        }
                        catch (ChefNodeCmdletExceptionBase e)
                        {
                            ThrowTerminatingError(new ErrorRecord(e, "ChefNodeCmdlet exception", ErrorCategory.InvalidResult, pipeClient));
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
                }

                // Summary:
                //  normalizes the node value from powershell for serialization.
                //
                // Returns:
                //  normalized value
                protected object GetNormalizedValue()
                {
                    return NormalizeValue(nodeValue);
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
                private static object NormalizeValue(object rawValue)
                {
                    if (null == rawValue)
                    {
                        return null;
                    }
                    if (rawValue is PSObject)
                    {
                        PSObject pso = (PSObject)rawValue;

                        return NormalizeValue(pso.BaseObject);
                    }
                    if (rawValue is Array)
                    {
                        // FIX: detect circular references.
                        return NormalizeArrayValue((Array)rawValue);
                    }
                    if (rawValue is IDictionary)
                    {
                        // FIX: detect circular references.
                        return NormalizeHashValue((IDictionary)rawValue);
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
                private static object NormalizeArrayValue(Array arrayValue)
                {
                    ArrayList copyArray = new ArrayList(arrayValue.Length);

                    foreach (object value in arrayValue)
                    {
                        copyArray.Add(NormalizeValue(value));
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
                private static object NormalizeHashValue(IDictionary hashValue)
                {
                    IDictionary copyHash = new Hashtable();

                    foreach (object key in hashValue.Keys)
                    {
                        object copyKey = NormalizeValue(key);
                        object copyValue = NormalizeValue(hashValue[key]);

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
