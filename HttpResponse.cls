Class NCA.FHIR.Process.HttpResponse Extends Ens.Response
{

Property StatusCode As %Integer;

Property ResponseBody As %String(MAXLEN = 1000);

Storage Default
{
<Data name="HttpResponseDefaultData">
<Subscript>"HttpResponse"</Subscript>
<Value name="1">
<Value>StatusCode</Value>
</Value>
<Value name="2">
<Value>ResponseBody</Value>
</Value>
</Data>
<DefaultData>HttpResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
