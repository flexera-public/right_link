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

namespace RightScale
{
    namespace Chef
    {
        namespace Protocol
        {
            public class Constants
            {
                public enum CommandType
                {
                    GET_CHEFNODE,
                    SET_CHEFNODE,
                }

                public static string CHEF_NODE_PIPE_NAME = "chef_node_D1D6B540-5125-4c00-8ABF-412417774DD5";

                public static int MAX_CLIENT_RETRIES = 10;

                public static int CHEF_NODE_CONNECT_TIMEOUT_MSECS = 30000;
                public static int SLEEP_BETWEEN_CLIENT_RETRIES_MSECS = 100;
            }
        }
    }
}
