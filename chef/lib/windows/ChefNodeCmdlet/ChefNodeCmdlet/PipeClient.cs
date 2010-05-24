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
using System.IO;
using System.IO.Pipes;

namespace RightScale
{
    namespace Common
    {
        namespace Protocol
        {
            // represents a generic text-based pipe client which communicates via a user-supplied transport.
            // the transport must convert requests/responses to discrete text messages delimited by newline.
            public class PipeClient
            {
                // Summary:
                //  constructor for a named pipe client.
                //
                // Parameters:
                //   pipeName:
                //      name of pipe to use when connecting to server.
                public PipeClient(string pipeName, ITransport transport)
                {
                    this.pipeName = pipeName;
                    this.transport = transport;
                }

                // Summary:
                //  creates a bidirectional pipe client.
                //
                // Parameters:
                //   timeoutMsecs:
                //      timeout on waiting for connection in milliseconds
                //
                // Throws:
                //   System.TimeoutException on failure to connect
                public void Connect(int timeoutMsecs)
                {
                    // create bidirectional pipe client.
                    pipeClient = new NamedPipeClientStream(pipeName);
                    pipeClient.Connect(timeoutMsecs);

                    // create writer.
                    streamWriter = new StreamWriter(pipeClient);
                    streamWriter.AutoFlush = true;

                    // create reader.
                    streamReader = new StreamReader(pipeClient);
                }

                // Summary:
                //  sends a request without waiting for a response.
                //
                // Parameters:
                //   request:
                //      request to send
                public void Send(object request)
                {
                    // send.
                    string text = transport.ConvertObjectToString(request);

                    streamWriter.WriteLine(text);
                }

                // Summary:
                //  sends/receives a request/response pair.
                //
                // Parameters:
                //   T:
                //      expected type for response
                //
                //   request:
                //      request to send
                //
                // Returns:
                //   received response object
                public T SendReceive<T>(object request)
                {
                    // send.
                    Send(request);

                    // receive.
                    {
                        string text = streamReader.ReadLine();

                        return (null == text) ? default(T) : transport.ConvertStringToObject<T>(text);
                    }
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
                    if (null != pipeClient)
                    {
                        try
                        {
                            pipeClient.Close();
                        }
                        catch (Exception)
                        {
                        }
                        pipeClient = null;
                    }
                }

                private ITransport transport = null;
                private NamedPipeClientStream pipeClient = null;
                private StreamReader streamReader = null;
                private StreamWriter streamWriter = null;
                private string pipeName = null;
            }
        }
    }
}
