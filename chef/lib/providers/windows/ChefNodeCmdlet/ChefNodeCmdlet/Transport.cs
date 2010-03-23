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
namespace RightScale
{
    namespace Common
    {
        namespace Protocol
        {
            public interface ITransport
            {
                // Summary:
                //  converts some data to text which can be sent via protocol.
                //
                // Parameters:
                //   data:
                //      object to convert to text
                //
                // Returns:
                //  converted data
                string ConvertObjectToString(object data);

                // Summary:
                //  converts some data to text which can be sent via protocol with optional pretty printing.
                //
                // Parameters:
                //   data:
                //      object to convert to text
                //
                //   pretty:
                //      true to insert pretty indentation for human readability.
                //
                // Returns:
                //  converted data
                string ConvertObjectToString(object data, bool pretty);

                // Summary:
                //  converts some data to an object of an expected type.
                //
                // Parameters:
                //   T:
                //      expected type of object
                //
                //   data:
                //      text to convert to object
                //
                // Returns:
                //  converted data
                T ConvertStringToObject<T>(string data);

                // Summary:
                //  normalizes the given object to strip away any implementation-dependent
                //  type information resulting from deserializing objects of unknown type.
                //  serialization libraries tend to default to their own internal types
                //  for collections and hashes (and sometimes for primitives) instead of
                //  relying on generics (usually because they are more efficient to
                //  deserialize and/or implement the ToString() method in a developer-
                //  friendly way). the problem with these internal types is that other
                //  libraries may encounter errors using them. on the other hand, support
                //  for generic collections of object is nearly universal.
                //
                // Parameters:
                //   data:
                //      data to convert, if necessary.
                //
                // Returns:
                //  normalized object
                object NormalizeDeserializedObject(object data);
            }
        }
    }
}
