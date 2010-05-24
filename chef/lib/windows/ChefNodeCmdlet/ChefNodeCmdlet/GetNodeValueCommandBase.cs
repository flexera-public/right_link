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
            // Provides a base class for get node commands.
            public abstract class GetNodeValueCommandBase : Cmdlet
            {
                // Path to distinguish child element being requested.
                [Parameter(ValueFromPipeline = true, Position = 0)]
                public string[] Path
                {
                    get { return path; }
                    set { path = value; }
                }

                // Summary:
                //  Factory method for request from cmdlet parameters.
                //
                // Returns:
                //  request object
                protected abstract GetNodeValueRequestBase CreateRequest();

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

                // Summary:
                //  implements required cmdlet processing method.
                protected override void ProcessRecord()
                {
                    // iterate attempting to connect, send and receive to Chef node server.
                    for (int tryIndex = 0; tryIndex < Constants.MAX_CLIENT_RETRIES; ++tryIndex)
                    {
                        ITransport transport = new JsonTransport();
                        PipeClient pipeClient = new PipeClient(Constants.CHEF_NODE_PIPE_NAME, transport);

                        try
                        {
                            GetNodeValueRequestBase request = CreateRequest();

                            pipeClient.Connect(Constants.CHEF_NODE_CONNECT_TIMEOUT_MSECS);

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

                            // can't write a null object to pipeline, so write nothing in the null case.
                            object nodeValue = responseHash.Contains(Constants.JSON_NODE_VALUE_KEY) ? responseHash[Constants.JSON_NODE_VALUE_KEY] : null;

                            if (null != nodeValue)
                            {
                                WriteObject(nodeValue, nodeValue is ICollection);
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

                private string[] path;
            }
        }
    }
}
