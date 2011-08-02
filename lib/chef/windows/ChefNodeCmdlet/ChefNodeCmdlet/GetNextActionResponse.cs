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

namespace RightScale
{
    namespace Chef
    {
        namespace Protocol
        {
            // data for a get-NextAction response
            public class GetNextActionResponse
            {
                public string NextAction
                {
                    get { return nextAction; }
                    set { nextAction = value; }
                }

                public GetNextActionResponse()
                {
                }

                public GetNextActionResponse(string nextAction)
                {
                    this.nextAction = nextAction;
                }

                public override string ToString()
                {
                    return String.Format("GetNextActionResponse: {{ NextAction \"{0}\" }}", nextAction);
                }

                private string nextAction;
            }
        }
    }
}
