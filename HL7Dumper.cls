Class NCA.HL7Dumper Extends Ens.BusinessProcess [ ClassType = persistent ]
{

Method OnRequest(pRequest As EnsLib.HL7.Message, Output pResponse As Ens.Response) As %Status
{
	set tsc = $$$OK
	// Dump HL7 content into an array
	do ..HL7Dumping(pRequest, .pArr)

	// Haitem El Aaouani 01/02/2023: Extract Message type / trigger event to monitor bundles
	Set TrigEvent = pRequest.GetValueAt("MSH:9.2")
	$$$TRACE("TrigEvent: "_TrigEvent)

	set BundleArray = ##class(%DynamicArray).%New()

	// Demographic bundle
	if TrigEvent = "A31" {
		Set BundleResources = $LISTBUILD("PatientResource", "GPPractitionerRoleResource", "ConsentResource",
									"OrganizationResource", "OrganizationResource", "PractitionerResource")
	}
	// Enconter bundle 
	Elseif $LISTBUILD("A01", "A02", "A03") [ TrigEvent {
		Set BundleResources = $LISTBUILD("PractitionerRoleResource", "PractitionerResource", "LocationResource",
									"EncounterResource", "EpisodeOfCareResource")
	}
	Else {
		quit $$$ERROR(5001,"unmanaged message type")
	}

	// Build the bundle and send to operation
	do ##Class(NCA.Resources).BundleBuilder(pArr, BundleResources, .BundleResource) // Bundle
	$$$TRACE("BundleResource.%ToJSON(): "_BundleResource.%ToJSON())
	set strmCont=##class(Ens.StreamContainer).%New()
	set strm = ##class(%Stream.GblChrCompress).%New()
	set formatter = ##class(%JSON.Formatter).%New()
	set Inputstring = BundleResource.%ToJSON()
	do formatter.FormatToStream(Inputstring, .strm)
	set strmCont.Stream=strm

	Set tsc=..SendRequestSync("NCAOps",strmCont)

	// Concept Map test
	set tsc = ##class(NCA.Resources).ConceptMapParams(.StremToConceptMap) // ConsentRequest
	Set tsc=..SendRequestSync("ConceptMaps", StremToConceptMap)

	quit tsc
}

Method HL7Dumping(pRequest As Ens.Request, Output pArr As %ArrayOfDataTypes) As %Status
{
	set tsc = $$$OK

	Set nhsNumber = ""
	Set LocalCode =  ""
	set pArr=##class(%ArrayOfDataTypes).%New()
	Set relationshipLKUP = "NCA.RelationShipCodes"
	Set genderLKUP = "NCA.GenderCode"
	Set ethnicityLKUP = "NCA.Ethnicity"

	// NHS Number / Local Code / OdsCode
	Set Count=pRequest.GetValueAt("PID:3(*)")
	For i=1:1:Count
	{	
		If (pRequest.GetValueAt("PID:3("_i_").5")="NHS")
		   	{
			   	Set nhsNumber=pRequest.GetValueAt("PID:3("_i_").1")
			   	Set nhsAssigner=pRequest.GetValueAt("PID:3("_i_").4")
		   	}
		If (pRequest.GetValueAt("PID:3("_i_").5")="DN")
		   	{
			   	Set LocalCode=pRequest.GetValueAt("PID:3("_i_").1")
			   	Set CodeAssigner=pRequest.GetValueAt("PID:3("_i_").4")
		   	}
	}

	if nhsNumber="" && LocalCode=""
	{
		quit $$$ERROR(5001,"The patient's NHS Number and Local code are missing within the Inbound HL7 message.")
	}

	do pArr.SetAt(nhsNumber, "NhsNumberContent.value")
	do pArr.SetAt(nhsAssigner, "NhsNumberAssigner")
	do pArr.SetAt(LocalCode, "LocalCode")
	do pArr.SetAt(CodeAssigner, "LocalCodeAssigner")
	do pArr.SetAt(pRequest.GetValueAt("PID:5.5"), "prefixContent")
	do pArr.SetAt(pRequest.GetValueAt("PID:5.1"), "nameContent.family")
	do pArr.SetAt(pRequest.GetValueAt("PID:5.2"), "givenNameContent.given")

	// Gender LookUp:
	Set GenderCode = ##class(Ens.Util.FunctionSet).Lookup(genderLKUP, pRequest.GetValueAt("PID:8"), "$D", "$DE")
	do pArr.SetAt(GenderCode, "resource.gender")

	// Date of birth
	do pArr.SetAt($ZDT($ZDATEH(pRequest.GetValueAt("PID:7.1"),5),3), "resource.birthDate")

	 // Ethnicity
	Set EthinicityCode = ##class(Ens.Util.FunctionSet).Lookup(ethnicityLKUP, pRequest.GetValueAt("PID:22.1"), "$D", "$DE")
	do pArr.SetAt(EthinicityCode, "ethnicCategory.value")
	$$$TRACE("EthinicityCode: "_EthinicityCode_"//"_pRequest.GetValueAt("PID:22.1"))

	do pArr.SetAt(pRequest.GetValueAt("PID:17"), "religion.value") // Religion
	do pArr.SetAt(pRequest.GetValueAt("PID:28"), "Nationality.value") // Nationality
	
    // BirthPlace
    do pArr.SetAt(pRequest.GetValueAt("PID:23"), "birthPlaceValueAddress.text")

	// Patient address
	do pArr.SetAt(pRequest.GetValueAt("PID:11.1"), "addressLines1")
	do pArr.SetAt(pRequest.GetValueAt("PID:11.2"), "addressLines2")
	do pArr.SetAt(pRequest.GetValueAt("PID:11.3"), "addressCity")
	do pArr.SetAt( pRequest.GetValueAt("PID:11.5"), "addressPostCode")

	// Deceased patient
	if pRequest.GetValueAt("PID:29") '= ""
	{
		set deceaseDay = $EXTRACT(pRequest.GetValueAt("PID:29"), 1, 8)
		set deceaseTime = $EXTRACT(pRequest.GetValueAt("PID:29"), 9, 10)_":"_$EXTRACT(pRequest.GetValueAt("PID:29"), 11, 12)_":"
		set deceaseTime = deceaseTime_$EXTRACT(pRequest.GetValueAt("PID:29"), 13, 17)_":"_$EXTRACT(pRequest.GetValueAt("PID:29"), 18, 19)

		do pArr.SetAt($ZDT($ZDATEH(deceaseDay,5),3)_"T"_deceaseTime, "resource.deceasedDateTime")
	}
	
	do pArr.SetAt(pRequest.GetValueAt("PID:11.1"), "addressLinesContent")
	do pArr.SetAt(pRequest.GetValueAt("PID:11.3"), "addressContent.city")
	do pArr.SetAt(pRequest.GetValueAt("PID:11.5"), "addressContent.postalCode")
	do pArr.SetAt(pRequest.GetValueAt("PID:13.1"), "phoneContent.value")
	do pArr.SetAt(pRequest.GetValueAt("PID:13.4"), "emailContent.value")

	// Next of Kin
	Set Cnt=pRequest.GetValueAt("NK1(*)")
	For j=1:1:Cnt
	{
		Set RelationShipCode = ##class(Ens.Util.FunctionSet).Lookup(relationshipLKUP, pRequest.GetValueAt("NK1("_j_"):3.1"), "$D", "$DE")
		do pArr.SetAt(RelationShipCode, "relationshipCodingCode.code"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):2.5"), "ContactprefixContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):2.2"), "ContactgivenNameContent.given"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):2.1"), "ContactnameContent.family"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):5"), "ContactphoneContent.value"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):6"), "ContactphoneBusinessContent.value"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.1"), "ContactAddressLinesContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.2"), "ContactAddressLinesOtherContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.3"), "ContactAddressLinesCityContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.4"), "ContactAddressLinesStateContent"_j)
		do pArr.SetAt(pRequest.GetValueAt("NK1("_j_"):4.5"), "ContactAddressContent.postalCode"_j)
	}

	// Practitioner
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.10"), "PASLocal")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.1"), "NationalCode")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.2"), "GPFamilyName")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.3"), "GPGivenName")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.6"), "GPPrefix")
	
	// Organization
	;do pArr.SetAt(pRequest.GetValueAt("PD1:3.3"), "odsOrganisationCode") //PD1:3.3 is for practitioner or Organization?
	;do pArr.SetAt(pRequest.GetValueAt("PD1:3.1"), "OrganisationName")

	do pArr.SetAt(pRequest.GetValueAt("PID:3.4"), "odsOrganisationCode") //PD1:3.3 is for practitioner or Organization?
	do pArr.SetAt(pRequest.GetValueAt("PID:3.1"), "OrganisationName")

	// ServiceRequest
	do pArr.SetAt(pRequest.GetValueAt("RF1:2"), "SRstatus")
	do pArr.SetAt(pRequest.GetValueAt("RF1:10"), "SRcategoryText")

    // Location
	do pArr.SetAt(pRequest.GetValueAt("PV1:3.1"), "LocationCode")
	do pArr.SetAt(pRequest.GetValueAt("PV1:3.9"), "LocationType")
	do pArr.SetAt(pRequest.GetValueAt("PV1:3.3"), "LocationName")

	// PraciontionerRole
	do pArr.SetAt(pRequest.GetValueAt("PV1:10"), "PractitionerRole.specialty") // Specialty

    // Episode Of Care
	do pArr.SetAt(pRequest.GetValueAt("EVN:2"), "EpisodeOfCareValue")
	
	// Encounter
	do pArr.SetAt(pRequest.GetValueAt("EVN:19"), "EncounterIdentifier")

	$$$TRACE("pArr Dumping: "_pArr.GetAt("NationalCode"))

	quit tsc
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
