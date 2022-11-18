Class NCA.Hl7toFhir Extends Ens.BusinessProcess [ ClassType = persistent ]
{

// Method CreateSubscription(MsgIn As EnsLib.HL7.Message, nhsNumber As %String, Output strmCont As Ens.StreamContainer) As %Status

Method OnRequest(pRequest As EnsLib.HL7.Message, Output pArr As Ens.Response) As %Status
{
	set tsc = $$$OK
	Set nhsNumber = ""
	Set LocalCode =  ""
	set pArr=##class(%ArrayOfDataTypes).%New()
	Set relationshipLKUP = "NCA.RelationShipCodes"

	// NHS Number / Local Code
	Set Count=pRequest.GetValueAt("PID:3(*)")
	For i=1:1:Count 
	{	
		If (pRequest.GetValueAt("PID:3("_i_").5")="NHS")
		   	{
			   	Set nhsNumber=(pRequest.GetValueAt("PID:3("_i_").1"))
			   	Set nhsAssigner=(pRequest.GetValueAt("PID:3("_i_").4"))
		   	}
		;pRequest.GetValueAt("PID:3("_i_").4")="RW6" && 
		If (pRequest.GetValueAt("PID:3("_i_").5")="DN")
		   	{
			   	Set LocalCode=(pRequest.GetValueAt("PID:3("_i_").1"))
		   	}
	}

	if nhsNumber="" && LocalCode=""
	{
		quit $$$ERROR(5001,"The patient's NHS Number and Local code are missing within the Inbound HL7 message.")
	}

	do pArr.SetAt(nhsNumber, "NhsNumberContent.value")
	do pArr.SetAt( nhsAssigner, "NhsNumberAssigner.display")
	do pArr.SetAt(LocalCode, "LocalCode")
	do pArr.SetAt(pRequest.GetValueAt("PID:5.5"), "prefixContent")
	do pArr.SetAt(pRequest.GetValueAt("PID:5.1"), "nameContent.family")
	do pArr.SetAt(pRequest.GetValueAt("PID:5.2"), "givenNameContent.given")

	// Gender LookUp:
	if pRequest.GetValueAt("PID:8") = "M"
	{
		do pArr.SetAt("male", "resource.gender")
	}
	elseif pRequest.GetValueAt("PID:8") = "F"
	{
		do pArr.SetAt("female", "resource.gender")
	}
	elseif pRequest.GetValueAt("PID:8") = "U"
	{
		do pArr.SetAt("unknown", "resource.gender")
	}
	elseif pRequest.GetValueAt("PID:8") = "I"
	{
		do pArr.SetAt("other", "resource.gender")
	}

	// Date of birth
	do pArr.SetAt($ZDT($ZDATEH(pRequest.GetValueAt("PID:7.1"),5),3), "resource.birthDate")

	// Patient address
	do pArr.SetAt(pRequest.GetValueAt("PID:11.1"), "addressLinesContent")
	do pArr.SetAt(pRequest.GetValueAt("PID:11.3"), "addressContent.city")
	do pArr.SetAt( pRequest.GetValueAt("PID:11.5"), "addressContent.postalCode")

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
		do pArr.SetAt(RelationShipCode_j, "relationshipCodingCode.code"_j)
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

	set tsc = ..PatientResource(pArr)

	// Practitioner
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.10"), "PASLocal")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.1"), "NationalCode")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.2"), "GPFamilyName")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.3"), "GPGivenName")
	do pArr.SetAt(pRequest.GetValueAt("PD1:4.6"), "GPPrefix")


	set tsc = ..PractitionerResource(pArr)

	

	quit tsc
}

// Patient Resource

Method PatientResource(pArr As Ens.Request) As %Status
{
	set tsc = $$$OK

	set nhsNumber = pArr.GetAt("NhsNumberContent.value")
	set nhsAssigner = pArr.GetAt("NhsNumberAssigner.display") 
	set LocalCode = pArr.GetAt("LocalCode")
	// Create a new subscription
	set resource = ##class(%DynamicObject).%New()
	
	// Create a "Resource Type" and add it to the subscription
	set resource.resourceType = "Patient"

	// NHS Number
	set identifierArray = ##class(%DynamicArray).%New()
	if nhsNumber
	{
		set NhsNumberContent = ##class(%DynamicObject).%New()
		Set NhsNumberAssigner = ##class(%DynamicObject).%New()
		set NhsNumberContent.system = "https://fhir.nhs.uk/Id/nhs-number"
		set NhsNumberContent.value = nhsNumber
		;set NhsNumberAssigner.reference = "https://fhir.hl7.org.uk/StructureDefinition/UKCore-Organization"
		set NhsNumberAssigner.display = nhsAssigner
		;set NhsNumberContent.assigner = "https://fhir.hl7.org.uk/StructureDefinition/UKCore-Organization/00000"
		set NhsNumberContent.assigner = NhsNumberAssigner

		do identifierArray.%Push(NhsNumberContent)
	}
	
	//ODS-Local: skip if the inbound HL7 doesn't have it
	if LocalCode
	{
		set LocalContent = ##class(%DynamicObject).%New()
		Set LocalAssigner = ##class(%DynamicObject).%New()
		set LocalContent.system = "ODS-Local"
		set LocalContent.value = LocalCode
		;set LocalAssigner.reference = "https://fhir.hl7.org.uk/StructureDefinition/UKCore-Organization"
		set LocalAssigner.display = "PAS-LOCAL"
		set LocalContent.assigner = LocalAssigner

		do identifierArray.%Push(LocalContent)
	}

	// push both identifiers: NHS Number + Local Code
	set resource.identifier = identifierArray

	// Name
	set nameArray = ##class(%DynamicArray).%New()
	set nameContent = ##class(%DynamicObject).%New()
	set nameContent.use = "official"
	
	Set prefixArray = ##class(%DynamicArray).%New() // Prefix: create a special object for prefix as it comes within an array
	Set prefixContent = ##class(%DynamicArray).%New()
	set prefixContent = pArr.GetAt("prefixContent")
	set prefixArray.prefix  = prefixContent
	set nameContent.prefix = prefixArray

	set nameContent.family = pArr.GetAt("nameContent.family")

	Set givenNameContent = ##class(%DynamicArray).%New() // Prefix: create a special object for prefix as it comes within an array
	set givenNameContent.given = pArr.GetAt("givenNameContent.given")
	set nameContent.given = givenNameContent

	do nameArray.%Push(nameContent)
	set resource.name = nameArray

	// If old name exists, then apply the same process

	// Gender
	set resource.gender = pArr.GetAt("resource.gender")

	// BirthDate
	/*
	set dob  = ##class(%DynamicObject).%New()
	set birthDateExtensionArray = ##class(%DynamicArray).%New()
	set birthDateExtensionContent = ##class(%DynamicObject).%New()

	set birthDateExtensionContent.url = "http://hl7.org/fhir/StructureDefinition/patient-birthTime"
	set birthDateExtensionContent.valueDateTime = $ZDT($ZDATEH(pRequest.GetValueAt("PID:7.1"),5),3)_"T00:00:00-00:00"

	do birthDateExtensionArray.%Push(birthDateExtensionContent)
	set dob.extension = birthDateExtensionArray
	*/

	set resource.birthDate = pArr.GetAt("resource.birthDate")
	;set resource.birthDate = dob

	//Deceased
	;set resource.deceasedBoolean = "true"
	if pArr.GetAt("resource.deceasedDateTime") '= ""
	{
		set resource.deceasedDateTime = pArr.GetAt("resource.deceasedDateTime")
	}

	//maritalStatus
	Set maritalStatus = ##class(%DynamicObject).%New()
	set maritalStatusCodingArray = ##class(%DynamicArray).%New()
	set maritalStatusCodingContent = ##class(%DynamicObject).%New()
	set maritalStatusCodingContent.system = "http://terminology.hl7.org/CodeSystem/v3-MaritalStatus"
	set maritalStatusCodingContent.code = "M"
	set maritalStatusCodingContent.display = "Married"
	do maritalStatusCodingArray.%Push(maritalStatusCodingContent)

	Set maritalStatus.coding = maritalStatusCodingArray
	set resource.maritalStatus = maritalStatus

	// Address
	set addressArray = ##class(%DynamicArray).%New()
	set addressContent = ##class(%DynamicObject).%New()

	set addressLinesArray = ##class(%DynamicArray).%New() // for address lines
	set addressLinesContent = ##class(%DynamicArray).%New()
	set addressLinesContent = pArr.GetAt("addressLinesContent")
	set addressLinesArray.line = addressLinesContent // Loop HL7 for address lines
	set addressContent.line = addressLinesArray

	set addressContent.city = pArr.GetAt("addressContent.city")
	set addressContent.postalCode = pArr.GetAt("addressContent.postalCode")
    set addressContent.country = "UK"

	do addressArray.%Push(addressContent)
	set resource.address = addressArray

	//telecom
	set telecomArray = ##class(%DynamicArray).%New()
	set phoneContent = ##class(%DynamicObject).%New()
	
	if pArr.GetAt("phoneContent.value") '= ""
	{
		set phoneContent.system = "phone"
		set phoneContent.value = pArr.GetAt("phoneContent.value")
		set phoneContent.use = "home"
		do telecomArray.%Push(phoneContent)
	}

	if pArr.GetAt("emailContent.value") '= ""
	{
		set emailContent = ##class(%DynamicObject).%New()
		set emailContent.system = "email"
		set emailContent.value = pArr.GetAt("emailContent.value")
		set emailContent.use = "work"
		do telecomArray.%Push(emailContent)

	}

	set resource.telecom = telecomArray

	// Contact
	
	set ContactContentArray  = ##class(%DynamicArray).%New()

	set j=1
	while pArr.GetAt("relationshipCodingCode.code"_j) '= ""
	{
		$$$TRACE(pArr.GetAt("ContactgivenNameContent.given"_j))
		set ContactContent  = ##class(%DynamicObject).%New()
		set CodeArray = ##class(%DynamicArray).%New()
		set relationshipArray = ##class(%DynamicArray).%New()
		set relationshipCoding = ##class(%DynamicObject).%New()
		set relationshipCodingCode = ##class(%DynamicObject).%New()

		set ContactnameContent = ##class(%DynamicObject).%New()
		Set ContactprefixArray = ##class(%DynamicArray).%New() // Prefix: create a special object for prefix as it comes within an array

		set ContacttelecomArray = ##class(%DynamicArray).%New()
		set ContactphoneContent = ##class(%DynamicObject).%New()

		set ContactAddressContent = ##class(%DynamicObject).%New()
		set ContactAddressLinesArray = ##class(%DynamicArray).%New() // for address lines

		set relationshipCodingCode.code = pArr.GetAt("relationshipCodingCode.code"_j)
		do CodeArray.%Push(relationshipCodingCode)
		set relationshipCoding.coding = CodeArray
		do relationshipArray.%Push(relationshipCoding)
		set ContactContent.relationship = relationshipArray

		set ContactprefixArray.prefix  = pArr.GetAt("ContactprefixContent"_j)
		set ContactnameContent.prefix = ContactprefixArray
		set ContactnameContent.given = pArr.GetAt("ContactgivenNameContent.given"_j)
		set ContactnameContent.family = pArr.GetAt("ContactnameContent.family"_j)
		set ContactContent.name = ContactnameContent

		set ContactphoneContent.system = "phone"
		set ContactphoneContent.value = pArr.GetAt("ContactphoneContent.value"_j)
		if ($EXTRACT(ContactphoneContent.value, 1, 2) = "07") || ($EXTRACT(ContactphoneContent.value, 1, 4) = "+447")
		{
			set ContactphoneContent.use = "mobile"
		}
		else
		{
			set ContactphoneContent.use = "home"
		}
		
		do ContacttelecomArray.%Push(ContactphoneContent)
		set ContactContent.telecom = ContacttelecomArray

		do ContactAddressLinesArray.%Push(pArr.GetAt("ContactAddressLinesContent"_j))
		do ContactAddressLinesArray.%Push(pArr.GetAt("ContactAddressLinesOtherContent"_j))
		do ContactAddressLinesArray.%Push(pArr.GetAt("ContactAddressLinesCityContent"_j))

		if pArr.GetAt("ContactAddressLinesStateContent"_j) '= ""
		{
			do ContactAddressLinesArray.%Push(pArr.GetAt("ContactAddressLinesStateContent"_j))
		}
		
		set ContactAddressContent.line = ContactAddressLinesArray

		;set ContactAddressContent.city = pArr.GetAt("ContactAddressLinesCityContent"_j)
		set ContactAddressContent.postalCode = pArr.GetAt("ContactAddressContent.postalCode"_j)
		set ContactContent.address = ContactAddressContent

		do ContactContentArray.%Push(ContactContent)

		$$$TRACE(ContactContentArray.%ToJSON())

		Set j = j+1
	}


	set resource.contact = ContactContentArray

	//Extension
	Set Extension = ##class(%DynamicArray).%New()

	// Extension - BirthPlace
	set birthPlace  = ##class(%DynamicObject).%New()
	set birthPlaceContent = ##class(%DynamicObject).%New()

	set birthPlaceContent.url = "http://hl7.org/fhir/StructureDefinition/patient-birthPlace"
	set birthPlaceContent.value = "Birth Place" // !!!! need to be address type???

	do Extension.%Push(birthPlaceContent)

	//Extension - Comments
	set commentsExtension  = ##class(%DynamicObject).%New()
	set commentsExtensionContent = ##class(%DynamicObject).%New()
	set commentsExtensionContent.url = "https://www.northerncarealliance.nhs.uk/fhir-profiles/PatientComments"
	set commentsExtensionContent.value= "This is a comment"
	do Extension.%Push(commentsExtensionContent)

	// Extension - ethnicCategory
	set ethnicCategory = ##class(%DynamicObject).%New()
	set ethnicCategoryContent = ##class(%DynamicObject).%New()

	set ethnicCategoryContent.url = "https://fhir.hl7.org.uk/StructureDefinition/Extension-UKCore-EthnicCategory" //!!! this link will import ethnic categories from wales and
	// and scotland as well!! Need to use england codes only?  "https://fhir.hl7.org.uk/CodeSystem/UKCore-EthnicCategoryEngland"
	set ethnicCategoryContent.value = "Ethnicity"

	do Extension.%Push(ethnicCategoryContent)

	// Extension - patientReligion
	set patientReligion = ##class(%DynamicObject).%New()
	set patientReligionContent = ##class(%DynamicObject).%New()

	set patientReligionContent.url = "http://hl7.org/fhir/StructureDefinition/patient-religion"
	set patientReligionContent.value = "Religion Code"

	do Extension.%Push(patientReligionContent)

	//Extension - Nationality
	set Nationality = ##class(%DynamicObject).%New()
	set NationalityContent = ##class(%DynamicObject).%New()

	set NationalityContent.url = "https://www.northerncarealliance.nhs.uk/fhir-profiles/patientNationality"
	set NationalityContent.value = "AF"

	do Extension.%Push(NationalityContent)

	//Extension - Occupation
	set Occupation = ##class(%DynamicObject).%New()
	set OccupationContent = ##class(%DynamicObject).%New()

	set OccupationContent.url = "https://www.northerncarealliance.nhs.uk/fhir-profiles/patientOccupation"
	set OccupationContent.value = "Nurse"

	do Extension.%Push(OccupationContent)

	//Extension - School
	set School = ##class(%DynamicObject).%New()
	set SchoolContent = ##class(%DynamicObject).%New()

	set SchoolContent.type = "edu"
	set SchoolContent.name = "School name"
	set SchoolContent.url = "https://www.northerncarealliance.nhs.uk/fhir-profiles/patientSchool"

	do Extension.%Push(SchoolContent)

	//GP
	set gpArray = ##class(%DynamicArray).%New()
	set gpContent  = ##class(%DynamicObject).%New()
	set gpContent.reference = "Practitioner/practitioner1"
	do gpArray.%Push(gpContent)

	set resource.generalPractitioner = gpArray
	
	//UKCore extensions
	set resource.extension = Extension
	zw resource
	$$$TRACE("resource="_resource.%ToJSON())

	// Add the Subscription into a streamContainer	
	/*
	set stream=##class(%Stream.GlobalCharacter).%New()
	set string = Subscription.%ToJSON()
	set tsc = stream.WriteLine(string)
	set strmCont=##class(Ens.StreamContainer).%New()
	set strmCont.Stream=stream
	*/
	
	Quit tsc
}

// Practitioner Resource

Method PractitionerResource(pArr As Ens.Request) As %Status
{
	set tsc = $$$OK

	set PASLocal = pArr.GetAt("PASLocal")
	set NationalCode = pArr.GetAt("NationalCode")
	set ADLocal = pArr.GetAt("ADLocal")

	set GPFamilyName=pArr.GetAt("GPFamilyName")
	set GPGivenName=pArr.GetAt("GPGivenName")
	set GPPrefix=pArr.GetAt("GPPrefix")

	// Create a new subscription
	set resource = ##class(%DynamicObject).%New()
	
	// Create a "Resource Type" and add it to the subscription
	set resource.resourceType = "Practitioner"

	// PAS Local
	set identifierArray = ##class(%DynamicArray).%New()
	if PASLocal '= ""
	{
		set PASLocalContent = ##class(%DynamicObject).%New()
		Set PASLocalAssigner = ##class(%DynamicArray).%New()
		Set PASLocalAssignerContent = ##class(%DynamicObject).%New()
		set PASLocalContent.system = "https://www.northerncarealliance.nhs.uk/PAS-LOCAL"
		set PASLocalContent.value = PASLocal
		set PASLocalAssignerContent.reference = "Organization/RW6orRM3"
		do PASLocalAssigner.%Push(PASLocalAssignerContent)
		set PASLocalContent.assigner = PASLocalAssigner

		do identifierArray.%Push(PASLocalContent)
	}

	// National Code
	if NationalCode '= ""
	{
		set NationalCodeContent = ##class(%DynamicObject).%New()
		Set NationalCodeAssigner = ##class(%DynamicObject).%New()
		set NationalCodeContent.system = "https://fhir.hl7.org.uk/Id/gmc-number"
		set NationalCodeContent.value = NationalCode
		do identifierArray.%Push(NationalCodeContent)
	}

	/*
	if ADLocal '= ""
	{
		set ADLocalContent = ##class(%DynamicObject).%New()
		Set ADLocalAssigner = ##class(%DynamicObject).%New()
		set ADLocalContent.system = "https://www.northerncarealliance.nhs.uk/PAS-LOCAL"
		set ADLocalContent.value = ADLocal //need to be looked up??
		set ADLocalAssigner.identifier = "RW6orRM3" //need to be looked up??
		set ADLocalContent.assigner = ADLocalAssigner

		do identifierArray.%Push(ADLocalContent)
	}
	*/

	set resource.identifier = identifierArray

	// GP Name
	set GPnameArray = ##class(%DynamicArray).%New()
	set GPnameContent = ##class(%DynamicObject).%New()
	Set GPnameAssigner = ##class(%DynamicObject).%New()
	set GPnameContent.use = "official"
	set GPnameContent.family = GPFamilyName
	set GPnameContent.given = GPGivenName
	set GPnameContent.prefix = GPPrefix
	do GPnameArray.%Push(GPnameContent)

	set resource.name = GPnameArray
	$$$TRACE("resource="_resource.%ToJSON())

	Quit tsc
}

Method OnResponse() As %Status
{
	$$$TRACE("Trace_OnResponse")
	q $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
