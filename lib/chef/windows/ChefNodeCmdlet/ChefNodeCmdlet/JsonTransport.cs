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
using System.Collections;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace RightScale
{
    namespace Common
    {
        namespace Protocol
        {
            // implements ITransport in terms of JSON serialization.
            public class JsonTransport : ITransport
            {
                string ITransport.ConvertObjectToString(object data)
                {
                    return JsonConvert.SerializeObject(data);
                }

                string ITransport.ConvertObjectToString(object data, bool pretty)
                {
                    return JsonConvert.SerializeObject(data, pretty ? Formatting.Indented : Formatting.None);
                }

                T ITransport.ConvertStringToObject<T>(string data)
                {
                    return JsonConvert.DeserializeObject<T>(data);
                }

                object ITransport.NormalizeDeserializedObject(object data)
                {
                    return NormalizeValue(data);
                }

                // Summary:
                //  implements normalization in terms of the inner types used by this
                //  JSON library. only handles known JSON types and returns any other
                //  types unchanged.
                //
                // Parameters:
                //   data:
                //      data to normalize.
                //
                // Returns:
                //  normalized data
                private static object NormalizeValue(object data)
                {
                    if (data is JValue)
                    {
                        JValue customValue = (JValue)data;

                        return customValue.Value;
                    }
                    if (data is JObject)
                    {
                        JObject jobject = (JObject)data;
                        Hashtable normalHash = new Hashtable();

                        foreach (JProperty jproperty in jobject.Properties())
                        {
                            string key = jproperty.Name;
                            object value = jproperty.Value;

                            normalHash[key] = NormalizeValue(value);
                        }

                        return normalHash;
                    }
                    if (data is JArray)
                    {
                        ICollection customCollection = (ICollection)data;
                        ArrayList normalCollection = new ArrayList(customCollection.Count);

                        foreach (object customObject in customCollection)
                        {
                            normalCollection.Add(NormalizeValue(customObject));
                        }

                        return normalCollection;
                    }

                    return data;
                }
            }
        }
    }
}
