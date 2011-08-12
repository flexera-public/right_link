/////////////////////////////////////////////////////////////////////////
// Copyright (c) 2010-2011 RightScale Inc
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
using System.IO;
using System.IO.Pipes;
using Newtonsoft.Json;

namespace RightScale
{
    namespace Common
    {
        namespace Protocol
        {
            // represents a generic text-based pipe server which communicates via a user-supplied transport.
            // the transport must convert requests/responses to discrete text messages delimited by newline.
            public class PipeServer
            {
                // Summary:
                //  constructor for a named pipe server.
                //
                // Parameters:
                //   pipeName:
                //      name of pipe to use when connecting to server.
                public PipeServer(string pipeName, ITransport transport)
                {
                    this.pipeName = pipeName;
                    this.transport = transport;
                }

                // Summary:
                //  creates a bidirectional pipe server and waits for client to connect.
                public void WaitForConnection()
                {
                    // create bidirectional pipe server.
                    pipeServer = new NamedPipeServerStream(pipeName);
                    pipeServer.WaitForConnection();

                    // create writer.
                    streamWriter = new StreamWriter(pipeServer);
                    streamWriter.AutoFlush = true;

                    // create reader.
                    streamReader = new StreamReader(pipeServer);
                }

                // Summary:
                //  receives the next request.
                //
                // Parameters:
                //   T:
                //      expected type for request
                //
                // Returns:
                //   received request object or null if client closed connection
                public T Receive<T>()
                {
                    string text = streamReader.ReadLine();

                    return (null == text) ? default(T) : transport.ConvertStringToObject<T>(text);
                }

                // Summary:
                //  sends the next response.
                //
                // Parameters:
                //   response:
                //      response object to send
                public void Send(object response)
                {
                    string text = transport.ConvertObjectToString(response);

                    streamWriter.WriteLine(text);
                }

                // Summary:
                //  closes the client and releases all resources.
                public void Close()
                {
                    if (null != streamReader)
                    {
                        try
                        {
                            streamReader.Close();
                        }
                        catch (Exception)
                        {
                        }
                        streamReader = null;
                    }
                    if (null != streamWriter)
                    {
                        try
                        {
                            streamWriter.Close();
                        }
                        catch (Exception)
                        {
                        }
                        streamWriter = null;
                    }
                    if (null != pipeServer)
                    {
                        try
                        {
                            pipeServer.Close();
                        }
                        catch (Exception)
                        {
                        }
                        pipeServer = null;
                    }
                }

                private ITransport transport = null;
                private NamedPipeServerStream pipeServer = null;
                private StreamReader streamReader = null;
                private StreamWriter streamWriter = null;
                private string pipeName = null;
            }
        }
    }
}
