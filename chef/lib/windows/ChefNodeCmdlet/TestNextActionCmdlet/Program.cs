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
using System.IO;
using System.IO.Pipes;
using RightScale.Chef.Protocol;
using RightScale.Common.Protocol;

namespace TestNextActionCmdlet
{
    class Program
    {
        static void Main(string[] args)
        {
            // resolve persistent node path.
            string pipeName = null;
            string nextActionPath = null;

            if (4 == args.Length && args[0] == "-pn" && args[2] == "-na")
            {
                pipeName = args[1];
                nextActionPath = args[3];
            }
            else
            {
                Console.WriteLine("Usage: -pn <pipe name> -na <next action file path>");
                Console.WriteLine();
                Console.WriteLine("The <pipe name> is any legal file name which uniquely distinguishes the pipe server.");
                Console.WriteLine("The <next action file path> is a text file containing a list of actions to execute in PowerShell.");
                return;
            }

            FileStream fileStream = null;
            StreamReader streamReader = null;

            try
            {
                // read next action file linewise.
                fileStream = new FileStream(nextActionPath, FileMode.OpenOrCreate, FileAccess.Read);
                streamReader = new StreamReader(fileStream);

                // use JSON transport to unmarshal initial nodes.
                ITransport transport = new JsonTransport();

                // create pipe server using JSON as transport.
                PipeServer pipeServer = new PipeServer(pipeName, transport);

                Console.WriteLine("Hit Ctrl+C to stop the server.");

                bool moreCommands = true;

                while (moreCommands)
                {
                    try
                    {
                        Console.WriteLine("Waiting for client to connect...");
                        pipeServer.WaitForConnection();

                        GetNextActionRequest request = pipeServer.Receive<GetNextActionRequest>();

                        if (null == request)
                        {
                            break;
                        }
                        Console.WriteLine(String.Format("Received: {0}", request.ToString()));

                        for (;;)
                        {
                            string nextLine = streamReader.ReadLine();

                            if (null == nextLine)
                            {
                                moreCommands = false;
                                nextLine = "exit";
                            }
                            if (nextLine.Trim().Length > 0)
                            {
                                GetNextActionResponse response = new GetNextActionResponse(nextLine);

                                Console.WriteLine(String.Format("Responding: {0}", response.ToString()));
                                pipeServer.Send(response);
                                break;
                            }
                        }
                    }
                    catch (Exception e)
                    {
                        Console.WriteLine(e.Message);
                    }
                    finally
                    {
                        pipeServer.Close();
                    }
                }
            }
            catch (IOException e)
            {
                Console.WriteLine(e.Message);
            }
            finally
            {
                if (null != streamReader)
                {
                    streamReader.Close();
                    streamReader = null;
                }
                if (null != fileStream)
                {
                    fileStream.Close();
                    fileStream = null;
                }
            }
        }
    }
}
