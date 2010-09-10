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
            // Provides the Set-NextAction cmdlet.
            [Cmdlet(VerbsCommon.Get, "NextAction")]
            public class GetNextActionCommand : Cmdlet
            {
                [Parameter(Position = 0, Mandatory = true)]
                public string PipeName
                {
                    get { return pipeName; }
                    set { pipeName = value; }
                }

                [Parameter(Position = 1, Mandatory = false)]
                public int LastActionExitCode
                {
                    get { return lastActionExitCode; }
                    set { lastActionExitCode = value; }
                }

                [Parameter(Position = 2, Mandatory = false)]
                public string LastActionErrorMessage
                {
                    get { return lastActionErrorMessage; }
                    set { lastActionErrorMessage = value; }
                }

                protected override void ProcessRecord()
                {
                    // iterate attempting to connect, send and receive to Chef node server.
                    for (int tryIndex = 0; tryIndex < Constants.MAX_CLIENT_RETRIES; ++tryIndex)
                    {
                        ITransport transport = new JsonTransport();
                        PipeClient pipeClient = new PipeClient(PipeName, transport);

                        try
                        {
                            GetNextActionRequest request = new GetNextActionRequest(LastActionExitCode, LastActionErrorMessage);

                            pipeClient.Connect(Constants.NEXT_ACTION_CONNECT_TIMEOUT_MSECS);

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
                                    throw new GetNextActionException(message);
                                }
                            }
                            if (ChefNodeCmdletExceptionBase.HasError(responseHash))
                            {
                                throw new GetNextActionException(responseHash);
                            }

                            // next action cannot be null.
                            string nextAction = responseHash.Contains(Constants.JSON_NEXT_ACTION_KEY) ? responseHash[Constants.JSON_NEXT_ACTION_KEY].ToString() : null;

                            if (null == nextAction)
                            {
                                throw new GetNextActionException("Received null for next action; expecting an exit command when finished.");
                            }

                            // enhance next action with try-catch logic to set the $global:RS_LastErrorRecord variable
                            // in case of an exception thrown by a script. the try-catch block loses details of script
                            // execution if caught by an outer block instead of the inner block which threw it.
                            nextAction = NEXT_ACTION_PREFIX + nextAction + NEXT_ACTION_POSTFIX;

                            // automagically convert next action into an invocable script block.
                            //
                            // example of use:
                            //
                            //  while ($TRUE)
                            //  {
                            //      $Error.clear()
                            //      $nextAction = $NULL
                            //      $nextAction = get-NextAction $pipeName
                            //      if ($Error.Count -eq 0)
                            //      {
                            //          write-output $nextAction
                            //          Invoke-Command -scriptblock $nextAction
                            //          sleep 1
                            //      }
                            //      else
                            //      {
                            //          break
                            //      }
                            //  }
                            ScriptBlock scriptBlock = ScriptBlock.Create(nextAction);

                            WriteObject(scriptBlock);

                            // done.
                            break;
                        }
                        catch (TimeoutException e)
                        {
                            ThrowTerminatingError(new ErrorRecord(e, "Connection timed out", ErrorCategory.OperationTimeout, pipeClient));
                        }
                        catch (GetNextActionException e)
                        {
                            ThrowTerminatingError(new ErrorRecord(e, "get-NextAction exception", ErrorCategory.InvalidResult, pipeClient));
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

                protected int       lastActionExitCode;        // The exit code of the last action that was run
                protected string    lastActionErrorMessage;    // The text of the error that occurred running the last action
                protected string    pipeName;                  // Name of pipe to connect to passed from command line

                private static string NEXT_ACTION_PREFIX =
@"try
{
    ";
                private static string NEXT_ACTION_POSTFIX =
@"
}
catch
{
    if ($NULL -eq $global:RS_lastErrorRecord)
    {
        $global:RS_lastErrorRecord = $_
    }
}";
            }
        }
    }
}
