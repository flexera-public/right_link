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

namespace RightScale
{
    namespace Powershell
    {
        namespace Exceptions
        {
            // Summary:
            //      base exception class for exceptions thrown by common code.
            class ChefNodeCmdletExceptionBase : Exception
            {
                public static string ERROR_KEY = "Error";
                public static string DETAIL_KEY = "Detail";

                public ChefNodeCmdletExceptionBase()
                    : base()
                {
                }

                public ChefNodeCmdletExceptionBase(Exception e)
                    : base(e.Message, e)
                {
                }

                public ChefNodeCmdletExceptionBase(string message)
                    : base(message)
                {
                }

                public ChefNodeCmdletExceptionBase(string message, Exception innerException)
                    : base(message, innerException)
                {
                }

                public ChefNodeCmdletExceptionBase(IDictionary response)
                    : base(CreateMessage(response))
                {
                }

                public static bool HasError(IDictionary response)
                {
                    return response.Contains(ERROR_KEY);
                }

                private static string CreateMessage(IDictionary response)
                {
                    string message = response[ERROR_KEY].ToString();

                    if (response.Contains(DETAIL_KEY))
                    {
                        message = String.Format("{0}\n{1}", message, response[DETAIL_KEY]);
                    }

                    return message;
                }
            }

            // exceptions for get-ChefNode cmdlet
            class GetChefNodeException : ChefNodeCmdletExceptionBase
            {
                public GetChefNodeException(string message)
                    : base(message)
                {
                }

                public GetChefNodeException(IDictionary response)
                    : base(response)
                {
                }

            }

            // exceptions for set-ChefNode cmdlet
            class SetChefNodeException : ChefNodeCmdletExceptionBase
            {
                public SetChefNodeException(string message)
                    : base(message)
                {
                }

                public SetChefNodeException(IDictionary response)
                    : base(response)
                {
                }
            }

            // exceptions for set-ChefNode cmdlet
            class GetNextActionException : ChefNodeCmdletExceptionBase
            {
                public GetNextActionException(string message)
                    : base(message)
                {
                }

                public GetNextActionException(IDictionary response)
                    : base(response)
                {
                }
            }
        }
    }
}
