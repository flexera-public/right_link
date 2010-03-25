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

namespace TestChefNodeCmdlet
{
    class Program
    {
        static void Main(string[] args)
        {
            // resolve persistent node path.
            string nodeFilePath = null;

            if (2 == args.Length && args[0] == "-nf")
            {
                nodeFilePath = args[1];
            }
            else
            {
                Console.WriteLine("Usage: TestChefNodeCmdlet -nf <nodefile>");
                Console.WriteLine();
                Console.WriteLine("The nodefile is a JSON text file containing initial values and which receives any modified node values.");
                return;
            }

            // load initial node values, if any.
            string nodeFileText = ReadTextFile(nodeFilePath);

            // use JSON transport to unmarshal initial nodes.
            ITransport transport = new JsonTransport();
            IDictionary nodeHash = new Hashtable();

            if (nodeFileText.Length > 0)
            {
                nodeHash = (IDictionary)transport.NormalizeDeserializedObject(transport.ConvertStringToObject<object>(nodeFileText));
            }

            // create pipe server using JSON as transport.
            PipeServer pipeServer = new PipeServer(Constants.CHEF_NODE_PIPE_NAME, transport);

            Console.WriteLine("Hit Ctrl+C to stop the server.");
            for (; ; )
            {
                try
                {
                    Console.WriteLine("Waiting for client to connect...");
                    pipeServer.WaitForConnection();
                    for (; ; )
                    {
                        IDictionary requestHash = (IDictionary)transport.NormalizeDeserializedObject(pipeServer.Receive<object>());

                        if (null == requestHash)
                        {
                            break;
                        }

                        string pathKey = "Path";
                        string nodeValueKey = "NodeValue";

                        if (1 == requestHash.Keys.Count && requestHash.Contains(pathKey))
                        {
                            GetChefNodeRequest request = new GetChefNodeRequest((ICollection)requestHash[pathKey]);
                            Console.WriteLine(String.Format("Received: {0}", request.ToString()));

                            object nodeValue = QueryNodeHash(nodeHash, request.Path);
                            GetChefNodeResponse response = new GetChefNodeResponse(request.Path, nodeValue);

                            Console.WriteLine(String.Format("Responding: {0}", response.ToString()));
                            pipeServer.Send(response);
                        }
                        else if (2 == requestHash.Keys.Count && requestHash.Contains(pathKey) && requestHash.Contains(nodeValueKey))
                        {
                            SetChefNodeRequest request = new SetChefNodeRequest((ICollection)requestHash[pathKey], requestHash[nodeValueKey]);
                            Console.WriteLine(String.Format("Received: {0}", request.ToString()));

                            InsertNodeHash(nodeHash, request.Path, transport.NormalizeDeserializedObject(request.NodeValue));

                            SetChefNodeResponse response = new SetChefNodeResponse(request.Path);
                            Console.WriteLine(String.Format("Responding: {0}", response.ToString()));
                            pipeServer.Send(response);

                            // save change to node file.
                            WriteTextFile(nodeFilePath, transport.ConvertObjectToString(nodeHash, true));
                        }
                        else
                        {
                            // unknown request type; hang up and try again.
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

        // Summary:
        //  inserts a node value at the hash depth indicated by path.
        //
        // Parameters:
        //   nodeHash:
        //      node hash
        //
        //   path:
        //      path into hash where each array element represents a level of hash depth.
        //
        //   nodeValue:
        //      node value to insert.
        private static void InsertNodeHash(IDictionary nodeHash, string[] path, object nodeValue)
        {
            for (int pathIndex = 0, pathCount = path.Length; pathIndex < pathCount; ++pathIndex)
            {
                string key = path[pathIndex];

                // insert node value if at end of path.
                if (pathIndex + 1 == pathCount)
                {
                    if (nodeHash.Contains(key))
                    {
                        nodeHash.Remove(key);
                    }
                    nodeHash.Add(key, nodeValue);
                }
                else
                {
                    // insert/update a child hash and continue.
                    IDictionary subHash = null;

                    if (nodeHash.Contains(key))
                    {
                        object child = nodeHash[key];

                        if (child is IDictionary)
                        {
                            subHash = (IDictionary)child;
                        }
                        else
                        {
                            nodeHash.Remove(key);
                        }
                    }
                    if (null == subHash)
                    {
                        subHash = new Hashtable();
                        nodeHash.Add(key, subHash);
                    }
                    nodeHash = subHash;
                }
            }
        }

        // Summary:
        //  queries a node value at the hash depth indicated by path.
        //
        // Parameters:
        //   nodeHash:
        //      node hash
        //
        //   path:
        //      path into hash where each array element represents a level of hash depth.
        //
        // Returns:
        //  node value to insert.
        private static object QueryNodeHash(IDictionary nodeHash, string[] path)
        {
            // special case for querying the root hash.
            if (1 == path.Length && 0 == path[0].Length)
            {
                return nodeHash;
            }
            for (int pathIndex = 0, pathCount = path.Length; pathIndex < pathCount; ++pathIndex)
            {
                string key = path[pathIndex];

                if (pathIndex + 1 == pathCount)
                {
                    return nodeHash.Contains(key) ? nodeHash[key] : null;
                }
                if (nodeHash.Contains(key))
                {
                    object child = nodeHash[key];

                    if (child is IDictionary)
                    {
                        nodeHash = (IDictionary)child;
                    }
                    else
                    {
                        break;
                    }
                }
                else
                {
                    break;
                }
            }

            return null;
        }

        // Summary:
        //  reads a text file and returns its content as a string.
        //
        // Parameters:
        //   filePath:
        //      path to text file
        //
        // Returns:
        //  text read from file or empty.
        public static string ReadTextFile(string filePath)
        {
            FileStream fileStream = null;
            StreamReader streamReader = null;

            try
            {
                fileStream = new FileStream(filePath, FileMode.OpenOrCreate, FileAccess.Read);
                streamReader = new StreamReader(fileStream);

                return streamReader.ReadToEnd();
            }
            catch (IOException)
            {
                return "";
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

        // Summary:
        //  writes the text given as a string to the given file.
        public static void WriteTextFile(string filePath, string text)
        {
            StreamWriter streamWriter = null;

            try
            {
                string parentDirPath = Path.GetDirectoryName(filePath);

                if (parentDirPath.Length > 0 && false == Directory.Exists(parentDirPath))
                {
                    Directory.CreateDirectory(parentDirPath);
                }

                streamWriter = File.CreateText(filePath);
                streamWriter.Write(text);
                streamWriter.Flush();
            }
            finally
            {
                if (null != streamWriter)
                {
                    try
                    {
                        streamWriter.Close();
                    }
                    catch (Exception)
                    {
                    }
                }
            }
        }
    }
}
