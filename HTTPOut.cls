Class NCA.HTTPOut Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

Parameter INVOCATION = "Queue";

Method SendFHIR(pMsgIn As Ens.StreamContainer, Output pResponse As Ens.Response)
{
	set tsc=$$$OK
	
	set strm=pMsgIn.Stream
	
	SET tHTTPReq=##class(%Net.HttpRequest).%New()	
	DO tHTTPReq.SetHeader("Content-Type","application/json")

	;SET ..Adapter.URL="http://hapi.fhir.org/baseR4"
	SET ..Adapter.URL="https://server.fire.ly"
	SET tHTTPReq.EntityBody=strm	
	
	SET tsc=..Adapter.SendFormDataArray(.tHttpResponse, "POST", tHTTPReq)
	
	#DIM tHttpResponse As %Net.HttpResponse
	
	set response=##class(NCA.HttpResponse).%New()

	set response.StatusCode= tHttpResponse.StatusCode
	set response.ResponseBody=tHttpResponse.Data.Read()
	
	set pResponse=response
	
	quit tsc
}

XData MessageMap
{
<MapItems>
<MapItem MessageType="Ens.StreamContainer">
<Method>SendFHIR</Method>
</MapItem>
</MapItems>
}

}
