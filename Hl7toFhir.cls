Class NCA.Hl7toFhir Extends Ens.BusinessProcess [ ClassType = persistent ]
{

// Method CreateSubscription(MsgIn As EnsLib.HL7.Message, nhsNumber As %String, Output strmCont As Ens.StreamContainer) As %Status

Method OnRequest(pRequest As EnsLib.HL7.Message, Output pResponse As Ens.Response) As %Status
{
	//ClassMethod PatientResource(pRequest As EnsLib.HL7.Message) As %Status
	//Extract nhsNumber from HL7 message
	set tsc = $$$OK
	Set nhsNumber = ""
	Set LocalCode =  ""
	Set Count=pRequest.GetValueAt("PID:3(*)")
	For i=1:1:Count 
	{	
		$$$TRACE(i_"//"_pRequest.GetValueAt("PID:3("_i_").5"))
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
	
	$$$TRACE("NHS No // nhsAssigner: "_nhsNumber)
	$$$TRACE("NHS No // nhsAssigner: "_nhsAssigner)
	$$$TRACE("LocalCode: "_LocalCode)

	if nhsNumber="" && LocalCode=""
	{
		quit $$$ERROR(5001,"The patient's NHS Number and Local code are missing within the Inbound HL7 message.")
	}

	set ^HL7Data("NhsNumberContent.value") = nhsNumber
	set ^HL7Data("NhsNumberAssigner.display") = nhsAssigner
	set ^HL7Data("LocalCode") = LocalCode
	set ^HL7Data("prefixContent") = pRequest.GetValueAt("PID:5.5")
	set ^HL7Data("nameContent.family") = pRequest.GetValueAt("PID:5.1")
	set ^HL7Data("givenNameContent.given") = pRequest.GetValueAt("PID:5.2")

	// Gender transformation:
	if pRequest.GetValueAt("PID:8") = "M"
	{
		set ^HL7Data("resource.gender") = "male"
	}
	elseif pRequest.GetValueAt("PID:8") = "F"
	{
		set ^HL7Data("resource.gender") = "female"
	}
	elseif pRequest.GetValueAt("PID:8") = "U"
	{
		set ^HL7Data("resource.gender") = "unknown"
	}
	elseif pRequest.GetValueAt("PID:8") = "I"
	{
		set ^HL7Data("resource.gender") = "other"
	}

	set ^HL7Data("resource.birthDate") =$ZDT($ZDATEH(pRequest.GetValueAt("PID:7.1"),5),3)
	set ^HL7Data("addressLinesContent") = pRequest.GetValueAt("PID:11.1")
	set ^HL7Data("addressContent.city") = pRequest.GetValueAt("PID:11.3")
	set ^HL7Data("addressContent.postalCode") = pRequest.GetValueAt("PID:11.5")
	if pRequest.GetValueAt("PID:29") '= ""
	{
		set deceaseDay = $EXTRACT(pRequest.GetValueAt("PID:29"), 1, 8)
		set deceaseTime = $EXTRACT(pRequest.GetValueAt("PID:29"), 9, 10)_":"_$EXTRACT(pRequest.GetValueAt("PID:29"), 11, 12)_":"
		set deceaseTime = deceaseTime_$EXTRACT(pRequest.GetValueAt("PID:29"), 13, 17)_":"_$EXTRACT(pRequest.GetValueAt("PID:29"), 18, 19)

		set ^HL7Data("resource.deceasedDateTime") = $ZDT($ZDATEH(deceaseDay,5),3)_"T"_deceaseTime
	}
	
	set ^HL7Data("addressLinesContent") = pRequest.GetValueAt("PID:11.1") 
	set ^HL7Data("addressContent.city") = pRequest.GetValueAt("PID:11.3")
	set ^HL7Data("addressContent.postalCode") = pRequest.GetValueAt("PID:11.5")
	set ^HL7Data("phoneContent.value") = pRequest.GetValueAt("PID:13.1")
	set ^HL7Data("emailContent.value") = pRequest.GetValueAt("PID:13.4")

	set ^HL7Data("relationshipCodingCode.code") = pRequest.GetValueAt("NK1.3")
	

	set tsc = ..PatientResource()

	kill ^HL7Data
	quit tsc
}

Method PatientResource() As %Status
{
	set tsc = $$$OK

	set nhsNumber = ^HL7Data("NhsNumberContent.value")
	set nhsAssigner = ^HL7Data("NhsNumberAssigner.display") 
	set LocalCode = ^HL7Data("LocalCode")
	// Create a new subscription
	set resource = ##class(%DynamicObject).%New()
	
	// Create a "Resource Type" and add it to the subscription
	set resource.resourceType = "Patient"

	// NHS Number
	if nhsNumber
		{
			set identifierArray = ##class(%DynamicArray).%New()
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
			set LocalArray = ##class(%DynamicArray).%New()
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
	set prefixContent = ^HL7Data("prefixContent")
	set prefixArray.prefix  = prefixContent
	set nameContent.prefix = prefixArray

	set nameContent.family = ^HL7Data("nameContent.family")

	Set givenNameContent = ##class(%DynamicArray).%New() // Prefix: create a special object for prefix as it comes within an array
	set givenNameContent.given = ^HL7Data("givenNameContent.given")
	set nameContent.given = givenNameContent

	do nameArray.%Push(nameContent)
	set resource.name = nameArray

	// If old name exists, then apply the same process

	// Gender
	set resource.gender = ^HL7Data("resource.gender")

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

	set resource.birthDate = ^HL7Data("resource.birthDate")
	;set resource.birthDate = dob

	//Deceased
	;set resource.deceasedBoolean = "true"
	if ^HL7Data("resource.deceasedDateTime") '= ""
	{
		set resource.deceasedDateTime = ^HL7Data("resource.deceasedDateTime")
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
	set addressLinesContent = ^HL7Data("addressLinesContent")
	set addressLinesArray.line = addressLinesContent // Loop HL7 for address lines
	set addressContent.line = addressLinesArray

	set addressContent.city = ^HL7Data("addressContent.city")
	set addressContent.postalCode = ^HL7Data("addressContent.postalCode")
    set addressContent.country = "UK"

	do addressArray.%Push(addressContent)
	set resource.address = addressArray

	//telecom
	set telecomArray = ##class(%DynamicArray).%New()
	set phoneContent = ##class(%DynamicObject).%New()
	
	if ^HL7Data("phoneContent.value") '= ""
	{
		set phoneContent.system = "phone"
		set phoneContent.value = ^HL7Data("phoneContent.value")
		set phoneContent.use = "home"
		do telecomArray.%Push(phoneContent)
	}

	if ^HL7Data("emailContent.value") '= ""
	{
		set emailContent = ##class(%DynamicObject).%New()
		set emailContent.system = "email"
		set emailContent.value = ^HL7Data("emailContent.value")
		set emailContent.use = "work"
		do telecomArray.%Push(emailContent)

	}

	set resource.telecom = telecomArray

	// Contact
	set ContactContent  = ##class(%DynamicObject).%New()
	
	set CodeArray = ##class(%DynamicArray).%New()
	set relationshipArray = ##class(%DynamicArray).%New()
	set relationship = ##class(%DynamicObject).%New()
	set relationshipCoding = ##class(%DynamicObject).%New()
	set relationshipCodingCode = ##class(%DynamicObject).%New()

	set relationshipCodingCode.code = "AMENDER"
	do CodeArray.%Push(relationshipCodingCode)
	set relationshipCoding.coding = CodeArray
	do relationshipArray.%Push(relationshipCoding)
	set ContactContent.relationship = relationshipArray

	set ContactnameContent = ##class(%DynamicObject).%New()
	set contactName = ##class(%DynamicObject).%New()
	Set ContactprefixArray = ##class(%DynamicArray).%New() // Prefix: create a special object for prefix as it comes within an array
	Set ContactprefixContent = ##class(%DynamicArray).%New()
	set ContactprefixContent = "Mrs"
	set ContactprefixArray.prefix  = ContactprefixContent
	set ContactnameContent.prefix = ContactprefixArray
	Set ContactgivenNameContent = ##class(%DynamicArray).%New() // Prefix: create a special object for prefix as it comes within an array
	set ContactgivenNameContent.given = "Given Name 1"
	set ContactnameContent.given = ContactgivenNameContent
	set ContactnameContent.family = "Family Name"
	set ContactContent.name = ContactnameContent

	set ContacttelecomArray = ##class(%DynamicArray).%New()
	set ContactphoneContent = ##class(%DynamicObject).%New()
	set ContactemailContent = ##class(%DynamicObject).%New()
	set ContactphoneContent.system = "phone"
	set ContactphoneContent.value = "0712312312"
	set ContactphoneContent.use = "mobile"
	set ContactemailContent.system = "email"
	set ContactemailContent.value = "email2@email2.com"
	set ContactemailContent.use = "home"
	do ContacttelecomArray.%Push(ContactphoneContent)
	do ContacttelecomArray.%Push(ContactemailContent)
	set ContactContent.telecom = ContacttelecomArray

	set ContactAddressContent = ##class(%DynamicObject).%New()
	set ContactAddressLinesArray = ##class(%DynamicArray).%New() // for address lines
	set ContactAddressLinesContent = ##class(%DynamicArray).%New()
	set ContactAddressLinesContent = "Contact address line 0" 
	set ContactAddressLinesArray.line = addressLinesContent // Loop HL7 for address lines
	set ContactAddressContent.line = addressLinesArray
	set ContactAddressContent.city = "city or line?"
	set ContactAddressContent.postalCode = "CT9 9CT"
    set ContactAddressContent.country = "UK"
	set ContactContent.address = ContactAddressContent

	set resource.contact = ContactContent

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
	
	quit tsc
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
